#!/usr/bin/perl
#
# recuperation des cartes BASULM, depuis le site http://basulm.ffplum.info/PDF/
#
# si $noSIA != 0 , ne recupere que les fichiers au format LFxxyy.pdf , ou xx sont 2 caracteres numeriques
#

use LWP::Simple;
use Data::Dumper;

use strict;

my $dirDownload = "basulm";    # le répertoire qui va contenir les documents pdf charges
my $URL = "http://basulm.ffplum.info/PDF/";

my $noSIA = 1;    # mettre a 1 pour ne recuperer que les fichiers pdf au format LFxxyy.pdf , ou xx sont 2 caracteres numeriques
                  # ceci elimine les fichiers comme LFEZ.pdf (aerodromes qui hébergent des ULM ; sont deja repertories bas base SIA)

{
  my $page = get($URL);
  die "Impossible de charger la page $URL" unless (defined($page));
    
  my $ads = &decodePage($page);
  
  mkdir $dirDownload;
  
  foreach my $ad (@$ads)
  {
    #next if ($ad !~ /^LF/);
    next if (($noSIA) && ($ad !~ /^LF\d\d..\.pdf$/));
	# next if ($ad =~ /^LF\d\d..\.pdf$/); # commenter le precedent, et decommenter celui-ci pour n'avoir que les fichiers en format "code SIA"
    my $urlPDF = $URL . $ad;
	#print "$urlPDF\n";
	print "$ad\n";
	
	my $status = getstore($urlPDF, "$dirDownload/$ad");   #download de la fiche pdf
    unless ($status =~ /^2\d\d/)
    {
	  print "code retour http $status lors du chargement du doc $urlPDF\n";
	  print "Arret du traitement\n";
	  exit 1;
	}
	sleep 1;
  }
}

#    ------------ decode la page html qui permet de choisir un terrain --------------------
# le code html est compose d'un tableau, avec une ligne comme la suivante par terrain :
# <tr><td valign="top">...</td><td><a href="LF0121.pdf">LF0121.pdf</a></td>...</tr>

sub decodePage
{
  my $page = shift;
  
  my @ads = ();     # va contenir le nom du fichier pdf
  my @lignes = split("\n", $page);
  foreach my $ligne (@lignes)
  {
    #print "$ligne\n";
	next unless ($ligne =~ /<tr>.* href=\"(.*?)\".*<\/tr>/);
      push(@ads, $1);
	}  
  return \@ads;
}
