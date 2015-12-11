#!/usr/bin/perl
#
# test de procedure de conversion de donnes geographiques
# on veut comparer des donnes issues de France.cup vers des donnes issues d'un export cvs de http://www.jprendu.fr/aeroweb/_private/21_JpRNavMaster/JpRNavMasterSearchPanel_Fr.html

use VAC;
use strict;

# cartes VAC
# LFEZ : LAT : 48 43 25 N  LONG : 006 12 23 E
# LFJD (CORLIER) : LAT : 46 02 23 N  LONG : 005 29 48 E

# "lat" et "long"     : vient des cartes VAC
# "lat1" et "long1"   : vient de France.cup
# lat_dec et long_dec : vient de JPR

#my $val = "48 43 25 N";
#my $res = &convertGPStoCUP($val);
#print "$val -> $res\n"; exit;

&convertBASULMtoCUP("N 44 47 37;E 005 45 42"); exit;

my %sites =
(
  LFEZ => { code => "LFEZ",     name => "Nancy Malzev Gld",           lat => "48 43 25 N", long => "006 12 23 E", lat1 => "4843.417N", long1 => "00612.383E", lat_dec => "48.7236", long_dec => "6.20639" },
  LF5453 => { code => "LF5453", name => "BouXIeres Grand",            lat => "48 45 58 N", long => "006 13 16 E", lat1 => "4845.967N", long1 => "00613.267E", lat_dec => "48.7661", long_dec => "6.22111" },
  LFDA => { code => "LFDA",     name => "Aire Sur L Adour",           lat => "43 42 31 N", long => "000 14 50 W", lat1 => "4342.483N", long1 => "00014.817W", lat_dec => "43.7086", long_dec => "-0.247222" },
  LFBZ => { code => "LFBZ",     name => "Biarritz Bayonne Anglet",    lat => "43 28 06 N", long => "001 31 52 W", lat1 => "4328.100N", long1 => "00131.867W", lat_dec => "43.4683", long_dec => "-1.53111" },
  LFJD => { code => "LFJD",     name => "Corlier",                    lat => "46 02 23 N", long => "005 29 48 E", lat1 => "4602.383N", long1 => "00529.783E", lat_dec => "46.0397", long_dec => "5.49667" },
  LFFH => { code => "LFFH",     name => "Chateau Thierry Belleau",    lat => "49 04 00 N", long => "003 21 20 E", lat1 => "4903.900N", long1 => "00321.017E", lat_dec => "49.0667", long_dec => "3.35556" },
  LFMX => { code => "LFMX",     name => "Château Arnoux Saint Auban", lat => "44 03 31 N", long => "005 59 27 E", lat1 => "4403.600N", long1 => "00559.450E", lat_dec => "44.0586", long_dec => "5.99083" },
  LFDJ => { code => "LFDJ",     name => "Pamiers les Pujols"          , lat => "43 05 26 N", long => "001 41 45 E", lat1 => "4305.433N", long1 => "00141.750E", lat_dec => "43.0906", long_dec => "1.69583" },
  LFGF => { code => "LFGF",     name => "Beaune Challanges"           , lat => "47 00 37 N", long => "004 53 47 E", lat1 => "4700.317N", long1 => "00453.600E", lat_dec => "47.1028", long_dec => "4.89639" },
    
);

{

  foreach my $site (keys %sites)
  {
    my $refSite = $sites{$site};
	# conversion GPS vers CUP
	printf ("%s. %s %s -> %s %s\n", $$refSite{name}, $$refSite{lat}, $$refSite{long}, &convertGPStoCUP($$refSite{lat}), &convertGPStoCUP($$refSite{long}));
	
	# conversion GPS vers format decimal
	# printf ("%s. %s %s -> %s %s\n", $$refSite{name}, $$refSite{lat},  $$refSite{long}, &convertGPStoDec($$refSite{lat}, 4), &convertGPStoDec($$refSite{long}, 4));
  }
}

sub convertBASULMtoCUP
{
  my $info = shift;
  
  die "|$info|. Format non reconnu" unless ($info =~ /(.*);(.*)/);
  my ($lat, $long) = ($1, $2);
  die "|$lat|. Latitude pas reconnue" unless ($lat =~ s/^N (.*)/\1 N/);
  die "|$long|. Longitude pas reconnue" unless ($long =~ s/^([EW]) (.*)/\2 \1/);
  
  my $newLat = &convertGPStoCUP($lat);
  my $newLong = &convertGPStoCUP($long);

  print "$lat   $long    =>   $newLat,$newLong\n";
}
