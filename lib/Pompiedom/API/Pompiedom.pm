package Pompiedom::API::Pompiedom;
use strict;
use warnings;
use Pompiedom::DB;
use AnyEvent::HTTP;
use Digest::SHA 'sha1_hex';
use Data::Dumper;
use Net::PubSubHubbub::Publisher;
use Coro 'async';

sub new {
    my ($klass, %args) = @_;

    $args{hostname} =~ s/:8086$//;

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

sub UserCanLogin {
    my ($self, $username, $password) = @_;
    my $encoded_password = sha1_hex($self->{hostname} . ':' . $password);
    return $self->{db}->UserCanLogin($username, $encoded_password);
}

sub FeedsAll {
    my ($self) = @_;

    my $feeds = $self->{db}->FeedsAll();

    for (@$feeds) {
        $_->{url} = 'http://'. $self->{hostname} . '/feed/' . $_->{shortcode} . '/rss.xml';
    }

    return $feeds;
}

sub UserFeeds {
    my ($self, $username) = @_;

    my $feeds = $self->{db}->UserFeeds($username);

    for (@$feeds) {
        $_->{url} = 'http://'. $self->{hostname} . '/feed/' . $_->{shortcode} . '/rss.xml';
    }

    return $feeds;
}

sub UserPostItem {
    my ($self, $feed_id, $post) = @_;
    return $self->{db}->UserPostItem($feed_id, $post);
}

sub FeedGet {
    my ($self, $shortcode) = @_;
    return $self->{db}->FeedGet($shortcode);
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
    my ($self, $feed_id) = @_;

    my $shortcode = $self->{db}->Scalar("SELECT `shortcode` FROM `feed` WHERE `id` = ?", $feed_id);

    my $cloud_url = 'http://cloud.stuifzand.eu:5337/rsscloud/ping';
    my $ping_form = 'url=http://'.$self->{hostname}.':8086/feed/'.$shortcode.'/rss.xml';

    http_post($cloud_url, $ping_form,
        headers => {
            'content-type' => 'application/x-www-form-urlencoded',
            'user-agent'   => 'pompiedom-river/0.1',
        }, sub {});

    return;
}

1;
