# Copyright (c) 2010-2013 Peter Stuifzand
# Copyright (c) 2010-2013 Other contributors as noted in the AUTHORS file
# 
# This file is part of Pompiedom.
# 
# Pompiedom is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
# 
# Pompiedom is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

package Pompiedom::Plack::App::OPML;
use strict;
use warnings;

use parent 'Plack::Component';

use Plack::Request;
use Plack::Session;
use URI;
use URI::Escape;
use XML::Feed;
use Encode;
use HTML::Entities 'encode_entities_numeric';

sub call {
    my $self = shift;
    my $env = shift;

    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    my $session = Plack::Session->new($env);

    my $templ = Template->new({
        INCLUDE_PATH => ['template/custom', 'templates/default' ],
        ENCODING     => 'utf8',
    });

    if ($req->path_info =~ m{^$}) {
        $res->content_type('text/x-opml; charset=UTF-8');


        my $out = <<"XML";
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
<head>
    <title>Community Reading List for shattr.net</title>
</head>
<body>
XML

        for my $feed (@{$env->{pompiedom_api}->FeedsAll}) {
            my $feed_name = encode_entities_numeric($feed->{name});
            my $feed_url = encode_entities_numeric($feed->{url});
            $out .= <<"XML";
    <outline text="$feed_name" htmlUrl="http://shattr.net"
    title="$feed_name" type="rss" version="RSS2" xmlUrl="$feed_url"  />
XML
        }

        $out .= "</body></opml>\n";

        $res->content($out);
    }
    else {
        return $req->new_response(404, [], 'Not found')->finalize;
    }

    return $res->finalize;
}

1;
