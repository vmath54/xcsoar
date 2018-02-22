#!/usr/bin/perl
#
# getInfosFromApiBasulm.pl
# 
# recuperation des infos BASULM, a partir de l'API specifique
# genere le fichier listULMfromAPI.csv, qui sera utilise par d'autres moulinettes
#
# Il faut au préalable demander une cle d'authentification a admin.basulm@orange.fr
#   Elle est ensuite accessible sur le site ffplum (https://basulm.ffplum.fr). cliquer sur MYBASULM
#
# doc de l'API basulm : https://basulm.ffplum.fr/mode-d-emploi-api.html
#
# pour essais de l'API, avec curl :
#    curl -H "Authorization: api_key <api_key>" "https://basulm.ffplum.fr/getbasulm/get/basulm/liste"
#    curl -H "Authorization: api_key <api_key>" "https:basulm.ffplum.fr/getbasulm/get/basulm/detail?id=5118"
#
#
# genere en sous-produit le resultat de la requete API brute, en format JSON : c'est le fichier basulm.json
#
# si exécuté sans parametre, donne de l'aide
#
# parametres acceptés :
#  . -key <api-key>. facultatif. C'est la clé API d'interrogation BASULM
#  . --replay : facultatif. Si present, permet de rejouer ce programme à partir du fichier basulm.json, sans interroger directement BASULM via l'API
#  . --verbose : facultatif. Si present, ne traite pas les terrains de basULM
#  . --help : facultatif. Affiche une  aide
#
# Un des deux paramètres '-key' ou '--replay' doivent être présents
#
# Exemple d'exécution :
# getInfosFromApiBasulm.pl -key xxxxxxxx



use VAC;
use JSON;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use Text::Unaccent::PurePerl qw(unac_string);

use Data::Dumper;

use strict;

my $baseURL = "https://basulm.ffplum.fr/getbasulm/get/basulm";  # url d'acces a l'API BASULM
my $listURL = "$baseURL/listall";                               # la liste des terrains. infos detailles
my $ficOUT = "listULMfromAPI.csv";                              # le fichier resultant


# des terrains nomenclatures dans les bases SIA ou BASULM, qu'on ne désire pas traiter
my $noADs = $VAC::noADs;

my $ficReference = "FranceVacEtUlm.cup";  # ce fichier va permettre d'ajouter l'information d'altitude pour ceux qui n'en ont pas, que QFU pour LF1757

my $verbose = 0;                          # A 1 pour avoir les infos de MaJ d'altitude qui ne peuvent pas etre recuperees du fichier basulm.csv										  

{
  my ($api_key, $replay, $help);
  
    my $ret = GetOptions
     ( 
       "key=s"          => \$api_key,
	   "replay"         => \$replay,
	   "h|help"         => \$help,
	 );
  
  die "parametre incorrect" unless($ret);
  &syntaxe() if ($help);
  &syntaxe() if (! defined($api_key) && ! defined($replay));

  my $page;   # va contenir le resultat de l'interrogation BASULM, en format JSON
  if ($api_key ne "")
  {
    my ($code, $cookies);
    ($code, $page, $cookies) = &sendHttpRequest($listURL, AUTHORIZATION => "api_key $api_key");
    die "Impossible de charger la page $listURL" unless (defined($page));
    { local(*OUTPUT, $/); open (OUTPUT, ">", "basulm.json") || die "can't open basulm.json"; print OUTPUT $page; close OUTPUT }; # ecrire resultat dans fichier
  }
  
  if (defined($replay))
    { local(*INPUT, $/); open (INPUT, "basulm.json") || die "can't open basulm.json"; $page = <INPUT>; close INPUT };  # pour lire le fichier basulm.json  

  my $baseULMs = &decodeInfosBASULM(\$page);  # decode les infos JSON recues de l'API BASULM
  # print Dumper($$baseULMs{LF5453});
  
  my $ULMs = &recoupeInfos($baseULMs, $ficReference);  # on recoupe les infos baseULM avec le fichier .CUP de reference
  #print Dumper($$ULMs{LF1522}); exit;
  
   die "unable to write fic $ficOUT" unless (open (FICOUT, ">$ficOUT"));
  foreach my $code (sort keys %$ULMs)
  {
    my $ULM = $$ULMs{$code};
    print FICOUT "$code;basulm;$$ULM{name};$$ULM{lat};$$ULM{long};$$ULM{elevation};$$ULM{nature};$$ULM{qfu};$$ULM{dimension};$$ULM{frequence};BASULM $$ULM{type}\n";
  }
  close FICOUT;
}

# recoupe les infos recues de BASULM avec les infos du fichier de reference  
sub recoupeInfos
{
  my $baseULMs = shift;
  my $ficRef = shift;
  
  my %natures = (  1 => "eau", 2 => "herbe", 3 => "neige", 5 => "dur" );  # codage dans fichier .CUP de ref
  
  my $ADRefs = &readRefenceCupFile($ficReference);    # infos de reference
  
  my %ULMs = ();      # le hash résultant
  
  foreach my $code (sort keys %$baseULMs)
  {
    #next if ($code ne "LF1522");
	
    my $AD = $$baseULMs{$code};    # C'est l'info brute, recuperee par l'API baseULM
	my $ADRef = $$ADRefs{$code};
	my $name = $$AD{name};		
	my $type = $$AD{type};
	$type = unac_string($type);
	$type =~ s/ $//;
    next if ($type =~ /ferme.? temporairement/i);
	next if ($type =~ /ferme.? definitivement/i);
	next if ($type =~ /temporairement ferme.?/i);
	next if ($type =~ /aerodrome ferme/i);
	next if ($type =~ /terrain mal defini/i);
	
	if ((! defined($ADRef)) && (! defined($$noADs{$code})))
	{
	  if ($$AD{elevation} ne "")
	  {
	    print "WARNING. $code;$name;$$AD{lat};$$AD{long};$$AD{elevation} . Ne se trouve pas dans la base de reference\n";
	  }
	  else
	  {
	    print "WARNING. $code;$name;$$AD{lat};$$AD{long}. Ne se trouve pas dans la base de reference. Pas d'altitude indiquee\n";
	  }
	}	
	
	my $infos = {name => $name, type => $type, code => $code, dimension => $$AD{dimension}};

	my $lat = $$AD{lat};
	my $long = $$AD{long};
	$lat =~ s/^N (.*)/\1 N/;
	$long =~ s/^([EW]) (.*)/\2 \1/;
    $$infos{lat} = $lat;
	$$infos{long} = $long;

	my $nature = $$AD{nature};
	$nature = "herbe" if ($nature eq "terre");
	#die "nature de terrain pas trouve : $code;$name;$nature\n" 
	if (($nature ne "dur") && ($nature ne "herbe") && ($nature ne "neige")&& ($nature ne "eau"))
	{                               # il n'y en a pas normalement
	  my $numNat = $$ADRef{nature};
	  if (defined($numNat))    
	  {
	    $nature = $natures{$numNat};
	    print "$code;$name. nature de terrain |$nature| recuperee du fichier de reference\n";
      }
	  else
	  {
	    die "$code;$name. Nature de terrain inconnue\n";
	  }
    }
	$$infos{nature} = $nature;
	
	my $elevation = $$AD{elevation};
	if ($elevation =~ /(\d+) ft/)
	{
	  $elevation = $1;
	}
	else
	{
	  if ($elevation eq "")   # pas d'altitude dans basulm. On prend celle du ficheir de ref
	  {
	    $elevation = $$ADRef{elevation};
	    if (defined($elevation))   # il y en a plusieurs
	    {
	      print "$code;$name. Altitude |${elevation}m| recuperee du fichier de reference\n" if ($verbose);
        }
	    else
	    {
	      print "WARNING. $code;$name. Altitude inconnue\n" if ($verbose);
	    }
	  }
	}
	$$infos{elevation} = $elevation if ($elevation ne "");
	
	my $qfu = $$AD{qfu};   # orientation preferee
	$qfu =~ s/^\'//;       # il y a parfois une quote en debut. A priori, plus vrai maintenant
	if ($qfu eq "")        # y a pas. On cherche dans oriention
	{   
	  if ($$AD{orientation} =~ /(\d\d)\-/)
	  {
	    $qfu = $1;
	  }
	  else
	  {
	    die "Impossible recuperer qfu : $name;$$AD{orientation}" if (($$AD{orientation} ne "omnidir") && ($$AD{orientation} ne "Inconnue"));
	  }
	}
	$$infos{qfu} = $qfu . "0" if ($qfu ne "");   # pour etre compatible avec le fichier .cup
	
	my $frequence = $$AD{frequence};
	$frequence =~ s/,/\./g;
	if (($frequence ne "") && ($frequence =~ /([\d\.]+)/))
	{
	  $frequence = $1;
	  $$infos{frequence} = $frequence;
	}
	
	$ULMs{$code} = $infos;
  }
  return \%ULMs;
}

###### decodage des infos JSON retournées par l'API BASULM ##################
sub decodeInfosBASULM
{
  my $page = shift;
  
  my %baseULM = ();
  my @infosRequired = ("name", "elevation", "lat", "long", "dimension", "nature", "type");
      
  my $json = decode_json($$page);
  die "la réponse BASULM n'est pas en format JSON. Voir fichier basulm.json" unless (defined($json));
  
  if ($$json{status} ne "ok")
  {
    print STDERR "Erreur dans la reponse BASULM : \n";
	print STDERR "code : $$json{error_code}, detail : $$json{error_description}\n";
	exit(1);
  }
    
  my $liste = $$json{liste};
  
  foreach my $AD (@$liste)
  {
	my $code = $$AD{code_terrain};
	next if ($code eq "");
	
	my $infos = {};
	$$infos{code} = $code;
	
	my $name = $$AD{toponyme};
	next if ($name eq "");
	$name =~ s/ $//;  # on retire un eventuel espace en fin
	$$infos{name} = $name;
	$$infos{type} = $$AD{type_terrain};
    $$infos{lat} = $$AD{latitude};
	$$infos{long} = $$AD{longitude};
	$$infos{elevation} = $$AD{altitude};
	$$infos{nature} = $$AD{nature_piste_1};
	$$infos{dimension} = $$AD{longueur_piste_1};
	$$infos{orientation} = $$AD{orientation_piste_1};
	$$infos{qfu} = $$AD{orientation_pref_1};
	$$infos{frequence} = $$AD{radio};
	
	foreach my $infosRequired (@infosRequired)
    {
	  unless (defined($$infos{$infosRequired}))
	  {	
	    print "$code. Impossible de recuperer l'info \"$infosRequired\" pour le terrain $code\n";
	    print "Arret du programme\n";
	    print Dumper($infos);
	    exit 1;
	  }
	}

	$baseULM{$code} = $infos;
  }
  return \%baseULM;
}

sub syntaxe
{
  print "getInfosFromApiBasulm.pl\n";
  print "Ce script permet d'interroger les donnees BASULM a l'aide de son API. Génère le fichier listULMfromAPI.csv\n";
  print "Génère en sous-produit le fichier basulm.json qui est le résultat brut de l'interrogation BASULM\n\n";
  print "les parametres sont :\n";
  print "  . -key <api-key>. facultatif. C'est la clé API d'interrogation BASULM\n";
  print "  . --replay : facultatif. Si present, permet de rejouer ce programme à partir du fichier basulm.json, sans interroger directement BASULM via l'API\n";
  print "  . --verbose : facultatif. Si present, ne traite pas les terrains de basULM\n";
  print "  . --help : facultatif. Affiche cette aide\n\n";
  print "Un des deux paramètres '-key' ou '--replay' doivent être présents\n";
  print "\n";
  
  exit;
}