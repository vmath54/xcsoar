#!/usr/bin/perl

# lecture du fichier basulm.csv, et generation d'un fichier plus facilement exploitable
#
# on a supprime 'a la main", dans excel, la colonne "Consignes" et les colonnes qui suivent "Radio" :
#   les colonnes "Consignes" et "Informations complémentaires" contiennent potentiellement des retour chariots, qui gênent la lecture
#   par effet de bord, les quotes qui bordent les différents champs ont ete supprimes par excel


use VAC;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $verbose = 0;                          # A 1 pour avoir les infos de MaJ d'altitude qui ne peuvent pas etre recuperees du fichier basulm.csv

my $ficIN = "basulm.csv";
my $ficOUT = "listULMfromCSV.csv";

my $ficReference = "FranceVacEtUlm.cup";  # ce fichier va permettre d'ajouter l'information d'altitude pour ceux qui n'en ont pas, que QFU pour LF1757
                                          # et de ne pas traiter les terrains BASULM qui sont egalement au SIA

# des terrains nomenclatures dans les bases SIA ou BASULM, qu'on ne désire pas traiter
my $noADs = $VAC::noADs;


my %natures = (  1 => "eau", 2 => "herbe", 3 => "neige", 5 => "dur" );
	
{
  my $ADRefs = &readRefenceCupFile($ficReference);    # infos de reference
  my $ULMs = &readFileBASULM($ficIN, $ADRefs);        # lecture de basulm.csv, et traitement
  
  my $nbre = scalar (keys %$ULMs);
  print "$nbre fiches trouvees\n";
  
  die "unable to write fic $ficOUT" unless (open (FICOUT, ">$ficOUT"));
  foreach my $code (sort keys %$ULMs)
  {
    #next if ($code ne "LF1757");
    my $ULM = $$ULMs{$code};
    print FICOUT "$code;basulm;$$ULM{name};$$ULM{frequence};$$ULM{elevation};$$ULM{lat};$$ULM{long};BASULM $$ULM{type};$$ULM{qfu};$$ULM{dimension};$$ULM{nature}\n";
  }
  close FICOUT;
}

sub readFileBASULM
{
  my $fic = shift;
  my $ADRefs = shift;
    
  my @infosRequired = ("name", "elevation", "lat", "long", "dimension", "nature");
  my %ULMs;
    
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));
  
  my $nbre = 0;
  
  my $line = <FIC>;     #on retire la premier ligne
  while (my $line = <FIC>)
  {
	chomp ($line);
	my ($obsolete, $code, $name, $type, $dateCreate, $dateModif, $dateValid, $position, $lat, $long, $elevation, $nbpistes, $piste1Nature, $piste1Pref, $piste1Larg, $piste1Long, $piste1Orient, $piste2Nature, $piste2Pref, $piste2Larg, $piste2Long, $piste2Orient, $frequence) = split(";", $line);

	next if ($code eq "");
	#next if ($code ne "LF2224");     #pour debug
	next if ($code =~ /^LF97\d\d$/);      # DOM TOM
	next if ($obsolete ne "");
	next if (defined($$noADs{$code}));

    my $ADRef = $$ADRefs{$code};
	
    my $infos = {};
	$name =~ s/ $//;  # on retire un eventuel espace en fin
	$$infos{name} = $name;
	$type = unac_string($type);
	$type =~ s/ $//;
	next if ($type eq "Base ULM fermee temporairement");
	next if ($type eq "Base ULM fermee definitivement");
	
	unless(defined($ADRef))
	{
	  print "WARNING. $code;$name. Ne se trouve pas dans la base de reference\n";
	  #exit;
	}
	
	my $cible = $$ADRef{cible};
	next if (($cible eq "vac") || ($cible eq "mil"));  # on ne traite pas les terrains qui sont repertories dau site SIA ou les bases militaires

	$nbre ++;
	
	$lat =~ s/^N (.*)/\1 N/;
	$long =~ s/^([EW]) (.*)/\2 \1/;
	$position =~ /(.*), (.*)/;
	my ($lat_dec, $long_dec) = ($1, $2);
	$$infos{type} = $type;
	$$infos{lat} = $lat;
	$$infos{long} = $long;
	$$infos{lat_dec} = $lat;
	$$infos{long_dec} = $long;
	if ($elevation =~ /(\d+) ft/)
	{
	  $elevation = $1;
	}
	else
	{
	  if (!defined($$infos{elevation}))
	  {
	    $elevation = $$ADRef{elevation};
	    if (defined($elevation))   # il y en a plusieurs
	    {
	      print "$code;$name. Altitude |${elevation}m| recuperee du fichier de reference\n" if ($verbose);
        }
	    else
	    {
	      print "WARNING. $code;$name. Altitude inconnue\n";
	    }
	  }
	}
	$$infos{elevation} = $elevation if (defined($elevation));
	
	$piste1Nature = "herbe" if ($piste1Nature eq "terre");
	#die "nature de terrain pas trouve : $code;$name;$nbpistes;$piste1Nature\n" 
	if (($piste1Nature ne "dur") && ($piste1Nature ne "herbe") && ($piste1Nature ne "neige")&& ($piste1Nature ne "eau"))
	{                               # il n'y en a pas normalement
	  my $numNat = $$ADRef{nature};
	  if (defined($numNat))    
	  {
	    my $nature = $natures{$numNat};
	    print "$code;$name. nature de terrain |$nature| recuperee du fichier de reference\n";
	    $piste1Nature = $nature;
      }
	  else
	  {
	    die "$code;$name. Nature de terrain inconnue\n";
	  }
    }
	$$infos{nature} = $piste1Nature;
	
	$$infos{dimension} = $piste1Long;
	# print "$name;$piste1Long;$piste1Pref;$piste1Orient\n" if ($piste1Long eq "");  # il y en a peu : terrains omnidir, glacier, ...
	
	my $qfu;
	unless (defined($$infos{qfu}))
	{
	  $qfu = $piste1Pref;
	  $qfu =~ s/^\'//;   # il y a parfois une quote en debut
	  if ($qfu eq "")
	  {   
	    if ($piste1Orient =~ /(\d\d)\-/)
	    {
	      $qfu = $1;
	    }
	    else
	    {
	      die "Impossible recuperer qfu : $name;$piste1Orient" if (($piste1Orient ne "'omnidir") && ($piste1Orient ne "'Inconnue"));
	    }
	  }
	  $$infos{qfu} = $qfu . "0" if ($qfu ne "");   # pour etre compatible avec le fichier .cup
	}
	
	$frequence =~ s/,/\./g;
	if (($frequence ne "") && ($frequence =~ /([\d\.]+)/))
	{
	  $frequence = $1;
	  # print "$code;$frequence\n";
	  $$infos{frequence} = $frequence;
	}
		
	foreach my $infosRequired (@infosRequired)
    {
	  unless (defined($$infos{$infosRequired}))
	  {	
	    print "$code. Impossible de recuperer l'info \"$infosRequired\" depuis le fichier $fic\n";
	    print "Arret du programme\n";
	    print Dumper($infos);
	    exit 1;
	  }
	}
	
    #if ($code eq "LF2224") {print Dumper($infos) ; exit;}
	$ULMs{$code} = $infos;
  }
  close FIC;
  
  return \%ULMs;
}

