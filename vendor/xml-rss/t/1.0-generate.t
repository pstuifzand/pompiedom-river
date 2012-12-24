use strict;
use warnings;

use Test::More;
plan tests => 25;

# 1
use_ok("XML::RSS");
use POSIX;

use constant DATE_TEMPLATE_LONG  => "%Y-%m-%dT%H:%M:%S%z";
use constant DATE_TEMPLATE_SHORT => "%Y/%m/%d";
use constant DATE_TEMPLATE_PUB   => "%c GMT";

my ($current_date, $short_date, $pub_date); 

BEGIN {
  $current_date = &POSIX::strftime(DATE_TEMPLATE_LONG, gmtime);
  $short_date   = &POSIX::strftime(DATE_TEMPLATE_SHORT, gmtime);
  $pub_date     = &POSIX::strftime(DATE_TEMPLATE_PUB,   gmtime);
}

use constant RSS_VERSION    => "1.0";
use constant RSS_SAVEAS     => "./t/generated/".RSS_VERSION."-generated.xml";
use constant RSS_MOD_PREFIX => "my";
use constant RSS_MOD_URI    => 'http://purl.org/my/rss/module/';

use constant RSS_CREATOR    => "joeuser\@example.com";
use constant RSS_ITEM_TITLE => "This is an item";
use constant RSS_ITEM_LINK  => "http://example.com/$short_date";
use constant RSS_ITEM_DESC  => "Yadda & yadda & yadda";
use constant RSS_XML_BASE   => "http://example.com/";

# 2
ok($current_date,"Current date:$current_date");

# 3
my $rss = XML::RSS->new(version => RSS_VERSION, 'xml:base' => RSS_XML_BASE);
isa_ok($rss,"XML::RSS");

# 4-5
cmp_ok($rss->{'version'},"eq",RSS_VERSION,"Version is ".RSS_VERSION);
cmp_ok($rss->{'xml:base'},"eq",RSS_XML_BASE,"Base is ".RSS_XML_BASE);

# 6-16
ok($rss->channel(
		 'title'          => "Test 1.0 Feed",
		 'link'           => "http://example.com/",
		 'description'    => "To lead by example",
		 'image'          => "http://example.com/example.gif",
		 'textinput'      => 'http://example.com/search.pl',
		 'dc' => {
			  date => $current_date,
			 },
		),"Set RSS channel");

ok($rss->image(
	       'title'       => 'Test Image',
	       'url'         => 'http://example.com/example.gif',
	       'link'        => 'http://example.com/',
	       'description' => 'Test Image',
	       'height'      => '25',
	       'weight'      => '144',
	      ),"Set RSS image");

ok($rss->textinput(
		   'title'       => 'Search',
		   'description' => 'Search for an example',
		   'name'        => 'q',
		   'link'        => 'http://example.com/search.pl',
		  ),"Set RSS text input");

ok($rss->add_item(
		  'title'       => RSS_ITEM_TITLE,
		  'link'        => RSS_ITEM_LINK,
		  'description' => RSS_ITEM_DESC,
		  'dc' => {
			   creator => RSS_CREATOR,
			   dc      => $short_date,
			  },
		 ),"Set one RSS item");


ok($rss->add_module(prefix=>RSS_MOD_PREFIX,uri=>RSS_MOD_URI),
   "Added namespace:".RSS_MOD_PREFIX);

ok($rss->add_module(prefix=>'creativeCommons',uri=>'http://backend.userland.com/creativeCommonsRssModule'),
   "Added namespace with uppercase letters in prefix");

# Dunno - some degree of weirdness
# with the constant that I don't
# feel like dealing with...
my $uri = RSS_MOD_URI;

cmp_ok($rss->{modules}->{$uri},
       "eq",
       RSS_MOD_PREFIX,
       "Namespace URI is ".RSS_MOD_URI);

my $as_string = $rss->as_string();
my $len = length($as_string);
ok($len,"RSS feed has '$len' characters");

ok($rss->save(RSS_SAVEAS),
   "Wrote to disk: ".RSS_SAVEAS);

my $file_contents;
{
    local $/;
    open I, "<", RSS_SAVEAS();
    $file_contents = <I>;
    close(I);
}

cmp_ok($file_contents,"eq",$as_string,RSS_SAVEAS." contains the as_string() result");

eval { $rss->parsefile(RSS_SAVEAS)};
is($@,'',"Parsed ".RSS_SAVEAS);

# 17
cmp_ok($rss->{channel}->{dc}{date},
       "eq",
       $current_date,
       "dc:date:".$current_date);

# 18
cmp_ok(keys(%{$rss->{namespaces}}),
       ">=",
       1,
       "RSS feed has atleast one namespace");

# 19
cmp_ok($rss->{'xml:base'}, "eq", RSS_XML_BASE, "Base is still ".RSS_XML_BASE);

# 20
cmp_ok(ref($rss->{'items'}),"eq","ARRAY","RSS object has an array of objects");

# 21 
cmp_ok(scalar(@{$rss->{'items'}}),"==",1,"RSS object has one item");

# 22
cmp_ok($rss->{items}->[0]->{title},"eq",RSS_ITEM_TITLE,RSS_ITEM_TITLE);

# 23
cmp_ok($rss->{items}->[0]->{link},"eq",RSS_ITEM_LINK,RSS_ITEM_LINK);

# 24 
cmp_ok($rss->{items}->[0]->{description},"eq",RSS_ITEM_DESC,RSS_ITEM_DESC);

# 25
cmp_ok($rss->{items}->[0]->{dc}->{creator},"eq",RSS_CREATOR,RSS_CREATOR);

__END__

=head1 NAME

1.0-generate.t - tests for generating RSS 1.0 data with XML::RSS.pm

=head1 SYNOPSIS

 use Test::Harness qw (runtests);
 runtests (./XML-RSS/t/*.t);

=head1 DESCRIPTION

Tests for generating RSS 1.0 data with XML::RSS.pm

=head1 VERSION

$Revision: 1.5 $

=head1 DATE

$Date: 2003/02/20 17:12:45 $

=head1 AUTHOR

Aaron Straup Cope

=head1 SEE ALSO

http://web.resource.org/rss/1.0

=cut
