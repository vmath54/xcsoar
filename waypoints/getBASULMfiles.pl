#!/usr/bin/perl
#
# recuperation des cartes BASULM, depuis le site http://basulm.ffplum.info/PDF/
#
# recupere 
#    - tous les fichiers au format "LFdddd.pdf" ou dddd sont des caracteres numériques
#    - et, pour les fichiers au format "LFss.pdf" où ss sont des caracteres non numériques
#        . si $noSIA == 0, tous ces fichiers sont recuperes
#        . sinon, ne récupère que ceux qui ne se trouvent pas dans le repertoire "$dirVAC" et le repertoire "$dirMIL" : ce sont des fichiers issus du site SIA ou des bases militaires
#                 ceci élimine, par exemple, les fichiers comme LFEZ.pdf
#

use LWP::Simple;
use Data::Dumper;

use strict;

my $dirDownload = "basulm";    # le répertoire qui va contenir les documents pdf charges
my $URL = "http://basulm.ffplum.info/PDF/";

my $dirVAC = "./vac";
my $dirMIL = "./mil";     
my $noSIA = 1;

{
  my $page = get($URL);
  die "Impossible de charger la page $URL" unless (defined($page));
  #print "$page\n"; exit;
  my $ads = &decodePage($page);   # la liste de tous les PDF
  
  my $SIAs = {};  # la liste des fichiers SIA et MIL
  if ($noSIA)
  {
    &listFicsSIA($dirVAC, $SIAs);
    &listFicsSIA($dirMIL, $SIAs);
  }

  mkdir $dirDownload;
  
  foreach my $ad (@$ads)
  {
    if ($noSIA && ($ad =~ /^LF\S\S$/) && defined($$SIAs{$ad}))
	{
	  # print "$ad dans basulm et SIA\n";
	  next;
	}

    my $urlPDF = $URL . $ad . ".pdf";
	#print "$urlPDF\n";
	print "$ad\n";
	
	my $status = getstore($urlPDF, "$dirDownload/$ad" . ".pdf");   #download de la fiche pdf
    unless ($status =~ /^2\d\d/)
    {
	  print "code retour http $status lors du chargement du doc $urlPDF\n";
	  print "Arret du traitement\n";
	  exit 1;
	}
	sleep 1;
  }
}

# ajoute au hash passe en second parametre les fichiers pdf qui sont dans le repertoire $rep. Ce sont, normalement, les fichiers issus des sites SIA ou MIL
sub listFicsSIA
{
  my $dir = shift;
  my $SIAs = shift;
  
  die "$dir n'est pas un repertoire" unless (-d $dir);
  
  my @fics = glob("$dir/*.pdf");
  return if (scalar(@fics) == 0);
  
  foreach my $ad (@fics)
  {
    my ($rep,$fic) = $ad =~ /(.+[\/\\])([^\/\\]+)$/;
    $fic =~ s/\.pdf$//;
	$$SIAs{$fic} = 1;
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
	  my $ad = $1;
	  $ad =~ s/\.pdf//;
	  next if (($ad !~ /^LF\d\d\d\d$/) && ($ad !~ /^LF\S\S$/));
      push(@ads, $ad);
	}  
  return \@ads;
}
