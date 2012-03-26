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

    my $rss = XML::RSS->new(version => '2.0');
    my $feed = $self->Hash("SELECT * FROM `feed` WHERE `shortcode` = ?", $shortcode);

    $rss->channel(
        title => $feed->{title},
        description => $feed->{description},
    );
    my $channel = $rss->channel;

    $channel->{cloud} = { 
        domain            =>'cloud.stuifzand.eu',
        port              => '5337',
        path              => '/rsscloud/pleaseNotify',
        registerProcedure => '',
        protocol          => 'http-post',
    };

    for my $item ($self->Hashes("SELECT * FROM `post` WHERE `feed` = ?", $feed->{id})) {
        $item->{guid} = $shortcode . '/' . $item->{id};
        my $pubDate = DateTime::Format::MySQL->parse_datetime($item->{published});
        $rss->add_item(
            title => $item->{title},
            'link'  => $item->{'link'},
            description => $item->{description},
            pubDate => DateTime::Format::Mail->format_datetime($pubDate),
            guid => $item->{guid},
        );
    }
    return $rss;
}

1;
