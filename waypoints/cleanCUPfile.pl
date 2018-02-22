#!/usr/bin/perl
#
# cleanCUPfile.pl
# 
# nettoie un fichier .cup provenant de SeeYou (je crois).
#   . supprime la première ligne, si celle-ci commence par "name,code,country,lat,lon,elev"
#   . ne conserve que les 11 premiers champs
#   . si l'altitude ou la dimension est de la forme '123.0m', elle est changée en '123m'
#   . supprime les doubles quotes (") autour de la frequence
#
# 2 arguments obligatoires :
#   . le fichier a lire
#   . le fichier a ecrire


use VAC;
use Data::Dumper;

use strict;
	
{
  my $nbargs = scalar(@ARGV);
  die "Erreur de syntaxe. il faut passer en parametres le fichier .cup a lire, et le nom du fichier a ecrire" if ($nbargs != 2);
  
  my $ficIN = $ARGV[0];
  my $ficOUT = $ARGV[1];

  die "unable to read fic $ficIN" unless (open (IN, "<$ficIN"));
  die "unable to write fic $ficOUT" unless (open (OUT, ">$ficOUT"));
  
  my $ind = 0;
  
  while (my $line = <IN>)
  {
	chomp ($line);
	next if ($line eq "");
	next if (($ind++ == 0) && ($line =~ /^name,code,country,lat,lon,elev/));
	
	my ($shortName, $code, $country, $lat, $long, $elevation, $nature, $qfu, $dimension, $frequence, $comment) = split(",", $line);
	$dimension =~ s/\.0m$/m/;
	$elevation =~ s/\.0m$/m/;
	$frequence =~ s/^"(.*)"$/$1/;

	print OUT "$shortName,$code,$country,$lat,$long,$elevation,$nature,$qfu,$dimension,$frequence,$comment\n";
  }
  close(IN);
  close(OUT);
}
