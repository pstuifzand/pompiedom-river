package Pompiedom::API::Pompiedom;
use strict;
use warnings;

use Pompiedom::DB;
use AnyEvent::HTTP;
use Digest::SHA 'sha1_hex';
use Data::Dumper;
use Net::PubSubHubbub::Publisher;
use Coro 'async';

use XML::RSS;
use DateTime::Format::Mail;
use DateTime::Format::MySQL;

sub new {
    my ($klass, %args) = @_;


    my $self = {
        hostname  => $args{hostname},
        db_config => $args{db_config},
    };

    my $db = Pompiedom::DB->Connect(%{ $self->{db_config} });

    $db->{DBH}{'mysql_enable_utf8'} = 1;
    $db->Execute("SET NAMES `utf8`");
    $self->{db} = $db;

    return bless $self, $klass;
}

sub hostname {
    my $self = shift;
    return $self->{hostname};
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
    return $self->{db}->Hashes(<<"SQL", $username);
SELECT `ef`.`id`, `ef`.`url`
FROM `ext_feed` AS `ef` 
LEFT JOIN `user_ext_feed` AS `uef` 
ON `ef`.`id` = `uef`.`feed_id`
LEFT JOIN `user` AS `u`
ON `uef`.`user_id` = `u`.`user_id`
WHERE `u`.`username` = ?
SQL
}

1;
