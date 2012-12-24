package Pompiedom::API::Pompiedom;
use strict;
use warnings;

use Plack::Util::Accessor qw(db_config river hostname);

use Pompiedom::DB;
use Pompiedom::Feed;
use AnyEvent::HTTP;
use Digest::SHA 'sha1_hex';
use Data::Dumper;
use Net::PubSubHubbub::Publisher;
use Coro 'async';
use Pompiedom::Feed;

use XML::RSS;
use DateTime::Format::Mail;
use DateTime::Format::MySQL;

sub new {
    my ($klass, %args) = @_;

    my $self = {
        hostname  => $args{hostname},
        db_config => $args{db_config},
        river     => $args{river},
    };

    my $db = Pompiedom::DB->Connect(%{ $self->{db_config} });

    $db->{DBH}{'mysql_enable_utf8'} = 1;
    $db->Execute("SET NAMES `utf8`");
    $self->{db} = $db;

    return bless $self, $klass;
}

sub UserCanLogin {
    my ($self, $username, $password) = @_;
    my $hostname = $self->hostname;
    $hostname =~ s/:8086$//;
    my $encoded_password = sha1_hex($hostname . ':' . $password);
    return $self->{db}->UserCanLogin($username, $encoded_password);
}

sub FeedsAll {
    my ($self) = @_;

    my $feeds = $self->{db}->FeedsAll();

    for (@$feeds) {
        $_->{url} = 'http://'. $self->hostname . '/feed/' . $_->{shortcode} . '/rss.xml';
    }

    return $feeds;
}

sub UserFeeds {
    my ($self, $username) = @_;

    my $feeds = $self->{db}->UserFeeds($username);

    for (@$feeds) {
        $_->{url} = 'http://'. $self->hostname . '/feed/' . $_->{shortcode} . '/rss.xml';
    }

    return $feeds;
}

sub UserPostItem {
    my ($self, $shortcode, $post) = @_;
    return $self->{db}->UserPostItem($shortcode, $post);
}

sub FeedGet {
    my ($self, $shortcode) = @_;

    my $hostname = $self->hostname;
    my $cloud = {
        domain            => 'cloud.stuifzand.eu',
        port              => '5337',
        path              => '/rsscloud/pleaseNotify',
        registerProcedure => '',
        protocol          => 'http-post',
    };
    my $pushub = 'http://shattr.superfeedr.com';

    my $feed_info = $self->{db}->FeedGetInfo($shortcode);

    my $rss = XML::RSS->new(version => '2.0');

    $rss->add_module(prefix => 'atom', uri => 'http://www.w3.org/2005/Atom');

    $rss->channel(
        title       => $feed_info->{title},
        description => $feed_info->{description},
        'link'      => 'http://'.$self->hostname . '/',
        cloud       => $cloud,
        atom        => [
            { el => 'link', val => { rel => "hub", href => $pushub } },
            { el => 'link', val => { rel => "self", href => "http://$hostname/feed/$shortcode/rss.xml", type => "application/rss+xml" } },
        ],
    );

    for my $item (@{$feed_info->{items}}) {
        my %entry;

        $item->{guid} = $shortcode . '/' . $item->{id};

        my $pubDate = DateTime::Format::MySQL->parse_datetime($item->{published});
        $pubDate->set_time_zone('Europe/Amsterdam');
        $entry{pubDate} = DateTime::Format::Mail->format_datetime($pubDate);

        for (qw/title link description guid/) {
            $entry{$_} = $item->{$_} if $item->{$_};
        }

        $rss->add_item(%entry);
    }

    return $rss;
}

sub PingFeed2 {
    my ($self, $feed_url, $hub_url) = @_;

    async {
        my $pub = Net::PubSubHubbub::Publisher->new(hub => $hub_url);

        $pub->publish_update($feed_url) or
            die "Ping failed: " . $pub->last_response->status_line;
    };
    return;
}

sub PingFeed {
    my ($self, $shortcode) = @_;

    my $cloud_url = 'http://cloud.stuifzand.eu:5337/rsscloud/ping';
    my $ping_form = 'url=http://'.$self->hostname.'/feed/'.$shortcode.'/rss.xml';

    http_post($cloud_url, $ping_form,
        headers => {
            'content-type' => 'application/x-www-form-urlencoded',
            'user-agent'   => 'pompiedom-river/0.1',
        }, sub {});

    return;
}

sub GetShortCodeForFeed {
    my ($self, $feed_id) = @_;
    return $self->{db}->Scalar("SELECT `shortcode` FROM `feed` WHERE `id` = ?", $feed_id);
}


sub GetUsernamesForFeed {
    my ($self, $url) = @_;
    return $self->{db}->FlatArray(<<"SQL", $url);
SELECT `u`.`username`
FROM `ext_feed` AS `ef` 
LEFT JOIN `user_ext_feed` AS `uef` 
ON `ef`.`id` = `uef`.`feed_id`
LEFT JOIN `user` AS `u`
ON `uef`.`user_id` = `u`.`user_id`
WHERE `ef`.`url` = ?
SQL
}

sub GetUserFeeds {
    my ($self, $username) = @_;

    return map { Pompiedom::Feed->new($_) } $self->{db}->Hashes(<<"SQL", $username);
SELECT `ef`.`id`, `ef`.`url`, `ef`.`mode`
FROM `ext_feed` AS `ef` 
LEFT JOIN `user_ext_feed` AS `uef` 
ON `ef`.`id` = `uef`.`feed_id`
LEFT JOIN `user` AS `u`
ON `uef`.`user_id` = `u`.`user_id`
WHERE `u`.`username` = ?
SQL

}

sub CreateUser {
    my ($self, $user) = @_;

    $self->{db}->Begin("CreateUser");

    eval {
        my $username = $user->{username};
        if ($username !~ m/^\w+$/) {
            die "Username should contain only a-z, 0-9, A-Z, _";
        }
        my $hostname = $self->hostname;
        $hostname =~ s/:8086$//;
        my $password = $user->{password};
        my $encoded_password = sha1_hex($hostname . ':' . $password);

        $self->{db}->Execute("INSERT INTO `user` (`username`, `password`, `created`) VALUES(?,?,NOW())",
            $username, $encoded_password);

        my $user_id = $self->{db}->InsertID();

        $self->{db}->Execute("INSERT INTO `feed` (`shortcode`, `title`) VALUES(?,?)",
            $username, $user->{fullname} . "'s short posts");

        my $feed_id = $self->{db}->InsertID();
        $self->{db}->Execute("INSERT INTO `user_feed` (`user_id`, `feed_id`) VALUES(?,?)",
            $user_id, $feed_id);

        my $url = 'http://shattr.net:8086/feed/'.$username.'/rss.xml';

        $self->{db}->Execute("INSERT INTO `ext_feed` (`url`, `created`) VALUES(?, NOW())", $url);
        my $ext_feed_id = $self->{db}->InsertID();

        $self->{db}->Execute("INSERT INTO `user_ext_feed` (`user_id`, `feed_id`) VALUES (?, ?)",
            $user_id, $ext_feed_id);

        $self->river->add_feed($url);
        $self->river->subscribe_cloud($url);

        $self->UserFollow($username, $url);

        $self->{db}->Commit("CreateUser");
    };
    if ($@) {
        my $err = $@;
        $self->{db}->Rollback();
        die $err;
    }
    return 1;
}

sub SaveFeed {
    my ($self, $feed) = @_;

    if ($feed->id) {
        my @args = (
            $feed->id,
            $feed->url, $feed->mode, $feed->status,
            $feed->updated, $feed->subscribed,
            $feed->hub, $feed->token,
            $feed->created, $feed->changed,
        );
        $self->{db}->Execute(<<"SQL", @args);
REPLACE INTO `ext_feed` (`id`, `url`, `mode`, `status`, `updated`, `subscribed`, `hub`, `token`, `created`, `changed`)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL
        die $@ if $@;

        my $cloud = $feed->cloud;
        if (!$cloud) {
            return;
        }

        my @cloud_args = (
            $feed->id,
            $cloud->domain||'',
            $cloud->port||'',
            $cloud->path||'',
            $cloud->register_procedure||'',
            $cloud->protocol||'',
        );
        $self->{db}->Execute(<<"SQL", @cloud_args);
REPLACE INTO `ext_feed_cloud`
    (`feed_id`, `domain`, `port`, `path`, `register_procedure`, `protocol`)
VALUES (?, ?, ?, ?, ?, ?)
SQL
        die $@ if $@;
    }
    else {
        my @args = (
            $feed->url, $feed->mode, $feed->status,
            $feed->updated, $feed->subscribed,
            $feed->hub, $feed->token,
            $feed->created, $feed->changed,
        );
        $self->{db}->Execute(<<"SQL", @args);
INSERT INTO `ext_feed` (`url`, `mode`, `status`, `updated`, `subscribed`, `hub`, `token`, `created`, `changed`)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL
        die $@ if $@;
        my $id = $self->{db}->InsertID();
        my $cloud = $feed->cloud;
        if (!$cloud) {
            return;
        }
        my @cloud_args = (
            $id,
            $cloud->domain||'',
            $cloud->port||'',
            $cloud->path||'',
            $cloud->register_procedure||'',
            $cloud->protocol||'',
        );
        $self->{db}->Execute(<<"SQL", @cloud_args);
INSERT INTO `ext_feed_cloud` (`feed_id`, `domain`, `port`, `path`, `register_procedure`, `protocol`)
VALUES (?, ?, ?, ?, ?, ?)
SQL
        die $@ if $@;
    }
    return;
}

sub GetAllExtFeeds {
    my $self = shift;

    return map { Pompiedom::Feed->new($_) } $self->{db}->Hashes(<<"SQL");
SELECT 
    `ef`.`id`, `ef`.`url`, `ef`.`mode`, `ef`.`status`, `ef`.`updated`, `ef`.`subscribed`, 
    `ef`.`hub`, `ef`.`token`, `ef`.`created`, `ef`.`changed`,
    `efc`.`domain`, `efc`.`port`, `efc`.`path`, `efc`.`register_procedure`, `efc`.`protocol`
FROM `ext_feed` AS `ef`
LEFT JOIN `ext_feed_cloud` AS `efc`
ON `ef`.`id` = `efc`.`feed_id`
SQL
}

sub UserFollow {
    my ($self, $username, $url) = @_;

    my $user_id = $self->{db}->Scalar("SELECT `user_id` FROM `user` WHERE `username` = ?", $username);
    my $feed_id = $self->{db}->Scalar("SELECT `id`  FROM `ext_feed` WHERE `url` = ?", $url);

    $self->{db}->Execute("REPLACE INTO `user_ext_feed` (`user_id`, `feed_id`) VALUES (?, ?)", $user_id, $feed_id);
    die $@ if $@;

    return;
}

1;
