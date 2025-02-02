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
#
# parametres facultatifs de ce script
#  . -partial <siteULM>. permet de faire une reprise des chargements à partie de ce site
#                        Utile si incident lors de l'opération, pour ne pas tout reprendre
#  . --help : facultatif. Affiche cette aide\n\n";  

use lib ".";       # necessaire avec strawberry, pour VAC.pm
use VAC;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use Data::Dumper;

use strict;

my $dirDownload = "basulm";    # le répertoire qui va contenir les documents pdf charges
my $URL = "https://basulm.ffplum.fr/PDF/";
my $ficULM = "listULMfromAPI.csv";

my $dirVAC = "./vac";
my $dirMIL = "./mil";     
my $noSIA = 1;

my $maxErrors = 10;         # nombre maxi de fiches impossibles a charger
my @adsInError = ();        # liste des fiches impossibles a charger

{
  my $partial;              # pour une reprise, à un terrain donné
  my $help;
  my $nbADs = 0;            # nb fiches chargees
  my $nbADsInError = 0;     # nb fiches que l'on n'a pas pu charger
  
  my $ret = GetOptions
   ( 
     "partial=s"       => \$partial,
	 "h|help"         => \$help,
   );
  
  die "parametre incorrect" unless($ret);
  &syntaxe() if ($help);

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
  
    next if (($partial ne "") && ($ad lt $partial));
	# exit if (-ad eq "LF3023"); pour arreter le chargement sur un site donné
  
    if ($noSIA && ($ad =~ /^LF\S\S$/) && defined($$SIAs{$ad}))
	{
	  # print "$ad dans basulm et SIA\n";
	  next;
	}

    my $urlPDF = $URL . $ad . ".pdf";
	#print "$urlPDF\n";
	print "$ad\n";
	
	my ($code, $pdf, $cookies) = &sendHttpRequest($urlPDF, SSL_NO_VERIFY => 1);
	
	if ($code =~ /^2\d\d/)
	{
  	  &writeBinFile("$dirDownload/$ad.pdf", $pdf);
	  $nbADs++;
	} else
	{
	  print "code retour http $code lors du chargement du doc $urlPDF\n";
	  $adsInError[$nbADsInError] = {AD => $ad, code => $code};
	  $nbADsInError++;
	  if ($nbADsInError == $maxErrors)
	  {
	    print "\n#### Arret du traitement. Trop d'erreurs : $nbADsInError ####\n";
		last;
	    #exit 1;
	  }
	}
	sleep 1;
  }
  print "\n";
  print "Nombre de fiches chargees  : $nbADs\n";
  print "Nombre de fiches en erreur : $nbADsInError\n";
  
  if ($nbADsInError > 0)
  {
	for (my $i = 0; $i < $nbADsInError; $i++)
	{
	  print "    $adsInError[$i]{AD} : $adsInError[$i]{code}\n";
	}
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

sub syntaxe
{
  print "getBASULMfiles.pl\n";
  print "Ce script permet de recuperer les cartes ULM sur le site BASULM\n";
  print "Il utilise en entree le fichier listULMfromAPI.csv, genere auparavant a l'aide du script getInfosFromApiBasulm.pl\n";
  print "les parametres facultatifs sont :\n";
  print "  . -partial <siteULM>. permet de faire une reprise des chargements a partie de ce site\n";
  print "                        Utile si incident lors de l'operation, pour ne pas tout reprendre\n";
  print "  . --help : facultatif. Affiche cette aide\n\n";
  print "Exemple :\n";
  print "getBASULMfiles.pl -partial \n";
  print "\n";
  
  exit;
}