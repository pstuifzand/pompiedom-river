package Pompiedom::DB;
use local::lib;
use strict;
use warnings;

use base 'DBIx::DWIW';


use XML::RSS;
use DateTime::Format::Mail;
use DateTime::Format::MySQL;

sub UserCanLogin {
    my ($self, $username, $encoded_password) = @_;
    return $self->Scalar(<<"SQL", $username, $encoded_password);
SELECT 1 
FROM `user` 
WHERE `username` = ? 
AND `password` = ?
SQL
}

sub FeedsAll {
    my ($self) = @_;

#SELECT `f`.`title` AS `name`, CONCAT('http://shattr.net/feed/',`f`.`shortcode`, '/rss.xml') AS `url`

    my $feeds = [ $self->Hashes(<<"SQL") ];
SELECT `f`.`title` AS `name`, `f`.`shortcode`
FROM `feed` AS `f`
SQL

    return $feeds;
}

sub UserFeeds {
    my ($self, $username) = @_;
#SELECT `uf`.`feed_id` AS `id`, `f`.`title` AS `name`, CONCAT('http://shattr.net/feed/',`f`.`shortcode`, '/rss.xml') AS `url`

    my $feeds = [ $self->Hashes(<<"SQL", $username) ];
SELECT `uf`.`feed_id` AS `id`, `f`.`title` AS `name`, `f`.`shortcode`
FROM `user` AS `u`
LEFT JOIN `user_feed` AS `uf`
ON `u`.`user_id` = `uf`.`user_id`
LEFT JOIN `feed` AS `f`
ON `uf`.`feed_id` = `f`.`id`
WHERE `u`.`username` = ?
SQL

    return $feeds;
}

sub UserPostItem {
    my ($self, $feed_id, $post) = @_;

    $self->Execute(<<"SQL", $post->{title}, $post->{link}, $post->{description}, $feed_id);
INSERT INTO `post` (`title`, `link`, `description`, `published`, `feed`)
VALUES (?, ?, ?, NOW(), ?)
SQL
}

sub FeedGet {
    my ($self, $shortcode) = @_;

    my $feed = $self->Hash("SELECT * FROM `feed` WHERE `shortcode` = ?", $shortcode);

    my $rss = XML::RSS->new(version => '2.0');
    $rss->add_module(prefix => 'atom', uri => 'http://www.w3.org/2005/Atom');

    $rss->channel(
        title       => $feed->{title},
        description => $feed->{description},
        'link'      => 'http://shattr.net:8086/',
        cloud       => {
            domain            => 'cloud.stuifzand.eu',
            port              => '5337',
            path              => '/rsscloud/pleaseNotify',
            registerProcedure => '',
            protocol          => 'http-post',
        },
        atom        => [
            { el => 'link', val => { rel => "hub", href => "http://shattr.superfeedr.com" } },
            { el => 'link', val => { rel => "self", href => "http://shattr.net:8086/feed/$shortcode/rss.xml", type => "application/rss+xml" } },
        ],
    );

    my @items = $self->Hashes("SELECT * FROM `post` WHERE `feed` = ? ORDER BY `published` DESC", $feed->{id});

    for my $item (@items) {
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

sub FeedItemSeen {
    my ($self, $guid) = @_;
    $self->Execute("INSERT INTO `feed_item_seen` (`guid`) VALUES(?)", $guid);
    return;
}

sub HaveFeedItemSeen {
    my ($self, $guid) = @_;
    return $self->Scalar("SELECT 1 FROM `feed_item_seen` WHERE `guid` = ?", $guid);
}

1;
