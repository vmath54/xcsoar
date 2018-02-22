#!/usr/bin/perl
#
# recuperation des cartes BASULM, depuis le site http://basulm.ffplum.info/PDF/<terrain>.pdf
#
# recupere 
#    - tous les fichiers au format "LFdddd.pdf" ou dddd sont des caracteres numériques
#    - et, pour les fichiers au format "LFss.pdf" où ss sont des caracteres non numériques
#        . si $noSIA == 0, tous ces fichiers sont recuperes
#        . sinon, ne récupère que ceux qui ne se trouvent pas dans le repertoire "$dirVAC" et le repertoire "$dirMIL" : ce sont des fichiers issus du site SIA ou des bases militaires
#                 ceci élimine, par exemple, les fichiers comme LFEZ.pdf
#
# Il faut disposer de la liste des terrains (le dossier n'est plus listable). On l'a à partir du fichier listULMfromAPI.csv, généré depuis le script getInfosFromApiBasulm.pl

use LWP::Simple;
use Data::Dumper;

use strict;

my $dirDownload = "basulm";    # le répertoire qui va contenir les documents pdf charges
my $URL = "http://basulm.ffplum.info/PDF/";
my $ficULM = "listULMfromAPI.csv";

my $dirVAC = "./vac";
my $dirMIL = "./mil";     
my $noSIA = 1;

my $reprise;
#my $reprise = "LF3358";    # a décommenter et valuer pour une reprise (éviter de recommencer au début)

{
  my $ads = &getADs($ficULM);     # la liste des codes terrain
  
  my $SIAs = {};  # la liste des fichiers SIA et MIL
  if ($noSIA)
  {
    &listFicsSIA($dirVAC, $SIAs);
    &listFicsSIA($dirMIL, $SIAs);
  }

  mkdir $dirDownload;
  
  foreach my $ad (@$ads)
  {
  
    next if (($reprise ne "") && ($ad lt $reprise));
  
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

# recuperation de la liste des codes terrain a partir du fichier listULMfromAPI.csv
sub getADs
{
  my $fic = shift;
  
  my @ADs;
  
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));

  while (my $line = <FIC>)
  {
	chomp ($line);
	next if ($line eq "");
	
	my ($code) = split(";", $line);
	next if ($code eq "");
	
	push(@ADs, $code);
  }
  close FIC;
  return \@ADs;
}