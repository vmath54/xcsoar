#!/usr/bin/perl
#
# utilitaire xcsoar
# generation d'un fichier de detail de waypoints permettant de relier un fichier vac pdf aux waypoints du fichier
#    FRA_FULL_HighRes.xcm, ou France.cup
# on utilise en entree la base WELT2000.txt, disponible a http://www.segelflug.de/vereine/welt2000/download/WELT2000.TXT
#
# il faudra deposer les fichiers pdf dans le dossier XCSoarData/vac
#
# voici un extrait du fichier genere :
# [ABBEVILLE GLD]
# file=vac/LFOI.pdf
#
# [AGEN LA GARENNE]
# file=vac/LFBA.pdf

use strict;

my $fic = "WELT2000.txt";
my $rep = "vac";

{
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));
  while (my $line = <FIC>)
  {
    chomp ($line);
 	next if ($line eq "");
	my $key = substr($line, 7, 16);
	my $code = substr($line, 23, 5);
	next unless ($code =~ s/^\#//);
	next unless ($code =~/^LF/);

	$key =~ s/ *$//;  # on supprime les espaces en fin
	$key =~ s/ +/ /sg; # on remplace les espaces multiples en un seul espace
	print "[$key]\n";
	print "file=$rep/$code.pdf\n";
	print "\n";
  }
  close FIC;
}