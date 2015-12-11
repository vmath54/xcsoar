#!/usr/bin/perl

# recuperation des informations relatives aux terrains a partir des fichier VAC pdf telecharges sur le site SIA
# utilise xpdf pour decoder les fichiers pdf
#
# on utilise egalement le fichier FranceVacEtUlm.cup en entree pour :
#   - detecter les nouvelles fiches
#   - ajouter les quelques infos qui pourraient manquer depuis les fichiers PDF
#        Concerne qfu, dimension et nature pour une dizaine de terra
#        et la fréquence :vide pour 2 terrains : LFIF et LFAK, et valuee pour 2 autres : LFBC et LFKS
#        mettre $verbose a 1 pour controler

use VAC;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $verbose = 1;                          # A 1 pour avoir les infos de MaJ qui ne peuvent pas etre recuperees des fichiers PDF
                                          #     (recupérées du fichier FranceVacEtUlm.cup)

my $dirVAC       = "vac";                 # le dossier qui contient les fichiers pdf VAC
my $dirMIL       = "mil";                 # le dossier qui contient les fichiers pdf MIL

my $ficOUT = "listVACfromPDF.csv";
my $ficReference = "FranceVacEtUlm.cup";  # ce fichier va permettre d'ajouter les informations qu'on n'a pas pu récupérer des fichiers PDF

# des terrains nomenclatures dans les bases SIA ou BASULM, qu'on ne désire pas traiter
my $noADs = $VAC::noADs;

my $bin = 'd:/soft/xpdfbin-win-3.04/bin64/pdftotext.exe';
#my $options = '-q -l 1';  #options a passer au binaire. "-q" : quiet . "-l 1" limite l'analyse a la 1ere page du PDF
my $options = '-q';        #options a passer au binaire. "-q" : quiet

my %cats = (  1 => "eau", 2 => "herbe", 3 => "neige", 5 => "dur" );

my $tempfile     = "tmp.txt";

########################### main #####################################
{
  my $VACs = {};

  my $ADRefs = &readRefenceCupFile($ficReference);  # infos de reference

  print "Recuperation depuis les fichiers SIA\n";
  &getInfosFromVACfiles($dirVAC, $VACs, $ADRefs, "vac");
  print "Recuperation depuis les fichiers de bases militaires\n";
  &getInfosFromVACfiles($dirMIL, $VACs, $ADRefs, "mil");
  
  my $nbre = scalar (keys %$VACs);
  print "$nbre fiches trouvées\n";

  die "unable to write fic $ficOUT" unless (open (FICOUT, ">$ficOUT"));  
  foreach my $code (sort keys %$VACs)
  {
    my $VAC = $$VACs{$code};
    print FICOUT "$$VAC{code};$$VAC{cible};$$VAC{name};$$VAC{frequence};$$VAC{elevation};$$VAC{lat};$$VAC{long};$$VAC{type};$$VAC{qfu};$$VAC{dimension};$$VAC{nature}\n";  
  }
}

############## recuperation des infos d'aerodromes depuis les fichiers pdf VAC #####
sub getInfosFromVACfiles
{
  my $dir = shift;
  my $VACs = shift;
  my $ADRefs = shift;
  my $cible = shift;
  
  my @fics = glob("$dir/*.pdf");

  unlink $tempfile;

  foreach my $fic (@fics)
  #my $fic = 'mil/LFSX.pdf';
  {
    my ($rep,$code) = $fic =~ /(.+[\/\\])([^\/\\]+)$/; 
	$code =~ s/\.pdf$//i;
	$code = uc($code);    # code du terrain, a partir du nom de fichier
    next if (defined($$noADs{$code}));

    my $cmd = "$bin $options $fic $tempfile";
	system($cmd);
	die "commande echouee" if ($? == -1);
	my $infos = &getInfosFromOneVACfile($code, $VACs, $ADRefs, $cible, $tempfile);  # recherche des infos du terrain, depuis le fichier genere a partir du pdf
	#print Dumper($infos); exit;
	unlink $tempfile;
  }
}

sub getInfosFromOneVACfile
{
  my $code = shift;
  my $VACs = shift;
  my $ADRefs = shift;
  my $cible = shift;
  my $fic = shift;

  my $infos =  {};
  my @infosRequired = ("elevation", "lat", "long", "type", "cat", "qfu", "dimension", "nature");  # name pas necessaire ; on recupere par ailleurs
    
  die "unable to read fic $fic" unless (open (FIC, "<$fic"));
  $$infos{code} = $code;
  $$infos{cible} = $cible;
  
  my $ADRef = $$ADRefs{$code};
  print "WARNING. $code n'est pas connu du fichier de référence\n" unless (defined($ADRef));
  
  my ($deb_qfu, $rwy) = (0, 0); # permet de savoir si on a atteint le moment des infos de type qfu, nature de terrain, ...
  while (my $line = <FIC>)
  {
    chomp ($line);
 	next if ($line eq "");
	################ cat : "AD", "AD-Hydro"
	if (!defined($$infos{cat}))
	{
	  $$infos{cat} = "AD" if (($line =~ /ATTERRISSAGE A VUE/) ||($line =~ /APPROCHE A VUE/));
	  $$infos{cat} = "AD-Hydro" if ($line =~ /AMERRISSAGE A VUE/);
	}
	$$infos{cat} = "AD-MIL" if ($cible eq "mil");
	
	############### nom du terrain ###################
	# NANCY MALZEVILLE AD2 LFEZ ATT 01
	# PERONNE SAINT QUENTIN AD 2 LFAG ATT 01
	#noter : "AD2" et "AD 2" ...
	if ((!defined($$infos{name})) && ($line =~ /(.*) AD *?2 $code/))
	{
	  my $name = $1;
	  $name =~ s/\f//;   # Dans certains cas (LFBS), on trouve le caractere 'form feed'
	  $$infos{name} = $name;
	}
	
	################# altitude #######################
	# ALT AD : 1247 (45 hPa) LFEZ
	# ALT AD : 1236 (44hPa) LFGW
	# ALT AD: 4255 (146 hPa) LAT : 45 15 14 N LONG : 006 48 04 E
	# ALT AD : -3 (0 hPa) LAT : 51 02 26 N LONG : 002 33 01 E
	# ALT SUP : 4830 (172 hPa) ALT INF : 4726 (168 hPa)
	# ALT AD SUP : 5193 (185 hPa) ALT AD INF : 5039 (180 hPa)
	# ALT Water AD : 0 (1 hPa) LFTB
	# Attention : altitude en pieds
	if ((! defined($$infos{elevation})) &&
	    (($line =~ /ALT AD : (\-*?\d+?) \(\d+? ?hPa\)/) || ($line =~ /ALT AD: (\-*?\d+?) \(\d+? ?hPa\)/) || ($line =~ /ALT Water AD : (\-*?\d+?) \(\d+? ?hPa\)/) || 
	     ($line =~ /ALT SUP : (\-*?\d+?) \(\d+? ?hPa\)/) || ($line =~ /ALT AD SUP : (\-*?\d+?) \(\d+? ?hPa\)/)))
	{
	  $$infos{elevation} = $1;
	}
	
	###################### latitude et longitude ##############
	# LAT : 48 43 25 N LONG : 006 12 23 E
	# LAT et LONG peuvent etre sur des lignes differentes
	# et on peut avoit ceci, uniquement sur une ligne (les infos LAT et LONG sont sur d'autres lignes)
	# 45 55 51 N 006 06 23 E
	unless (defined($$infos{lat}))
    {
	   $$infos{lat} = $1 if ($line =~ /LAT : (\d\d \d\d \d\d N)/);
	}
	unless (defined($$infos{long}))
	{
	  $$infos{long} = $1 if ($line =~ /LONG : (\d\d\d \d\d \d\d [WE])/);
	}	
	if ((! (defined($$infos{lat}))) && (! (defined($$infos{long}))))
	{
	  if ($line =~ /^(\d\d \d\d \d\d N) (\d\d\d \d\d \d\d [WE])$/)
	  {
	    $$infos{lat} = $1;
	    $$infos{long} = $2;
	  }
	}
	
	################# frequence ######################
	# APP : NIL TWR : NIL A/A : 136.1      (LFEZ)
	# APP : NIL TWR : NIL A/A 123.175      (LFAS)
	# A/A : 123.350 (commune avec / common with LENS)
	# APP : LORRAINE Approche/Approach - OCHEY Approche/Approach 127.250 TWR : NIL AFIS : 119.6 Absence AFIS : A/A (119.6) FR seulement /only      (LFSN)
	# parfois, la ligne commence par A/A
	#dans certains cas (ex : LFAK), il n'y a pas de frequence A/A
	$$infos{AA} = "NIL" if (! defined($$infos{AA}) && ($line =~ /A\/A : NIL/));
	$$infos{TWR} = "NIL" if (! defined($$infos{TWR}) && ($line =~ /TWR : NIL/));
	$$infos{AFIS} = "NIL" if (! defined($$infos{AFIS}) && ($line =~ /AFIS : NIL/));
	if (! defined($$infos{AA}) &&
	   (($line =~ /A\/A : ?([\d\.]+?)$/) || ($line =~ /A\/A : ?([\d\.]+?) /) || ($line =~ /A\/A ([\d\.]+?)$/) || ($line =~ /A\/A ([\d\.]+?) /)  ||
	    ($line =~ /A\/A \(([\d\.]+?)\)/) || ($line =~ /A\/A : \(([\d\.]+?)\)/) || ($line =~ /A\/A.*?([\d\.]+?)$/) || ($line =~ /A\/A.*?([\d\.]+?) /)))
	{
	  $$infos{AA} = $1 if ($1 ne ".");
	}

	if (! defined($$infos{TWR}) &&
	   (($line =~ /TWR : ?([\d\.]+?)$/) || ($line =~ /TWR : ?([\d\.]+?)[ -]/) || ($line =~ /TWR ([\d\.]+?)$/) || ($line =~ /TWR ([\d\.]+?) /) || 
	    ($line =~ /TWR \(([\d\.]+?)\)/) || ($line =~ /TWR : .*? ([\d\.]+?)$/) || ($line =~ /TWR : .*? ([\d\.]+?) /)))
	{
	  $$infos{TWR} = $1;
	}

	if (! defined($$infos{AFIS}) &&
	    (($line =~ /AFIS : ?([\d\.]+?)$/) || ($line =~ /AFIS : ?([\d\.]+?) /) || ($line =~ /AFIS ([\d\.]+?)$/) || ($line =~ /AFIS ([\d\.]+?) /) || 
		 ($line =~ /AFIS \(([\d\.]+?)\)/) || ($line =~ /AFIS : .*? ([\d\.]+?)$/) || ($line =~ /AFIS : .*? ([\d\.]+?) /)))
	{
	  $$infos{AFIS} = $1;
	}
		
	############## type : "Usage restreint", "Ouvert à la CAP", "Réservé administration" "MIL fermé à la CAP"
	if ((! defined($$infos{type})) &&
	    (($line =~ /([Oo]uvert à la CAP)/) ||($line =~ /([uU]sage restreint)/) || ($line =~ /^(Réservé administration)/)|| ($line =~ /^(MIL fermé à la CAP)/) ))
	{
	  $$infos{type} = ucfirst(unac_string($1));
	}
	
	################ pistes (qfu et dimension), nature ##################
	$deb_qfu = 1 if ((!$deb_qfu) && ($line =~ /RWY QFU?/));  # on demarre la section qui contient les infos de pistes
	$rwy = 1 if ($line =~ /^RWY$/);
	$deb_qfu = 1 if ((!$deb_qfu) && ($line =~ /^QFU?/));
	$deb_qfu = 1 if ((!$deb_qfu) && ($rwy) && ($line =~ /QFU/));
	if ($deb_qfu)
	{
	  if ($line =~ /RWY QFU (.*)/)
	  {
	    my $droit = $1;
	    if ($droit eq "Omnidirectionnel")
	    {
	      $$infos{qfu} = "";
		  $$infos{dimension} = "";
		  $$infos{nature} = "eau";
	    }
	    else
	    {
	      next unless ($droit =~ /\d/);
		  if (($droit =~ /^(\d\d) (\d\d\d)/) || ($droit =~ /^(\d\d) ?[RL] (\d\d\d)/))
		  {
		    my ($qfu1, $qfu2) = ($1, $2);    # direction 1ere piste. Ex : "09 092"
		    #print "$code;$qfu1;$qfu2\n";
		    $$infos{qfu} = $qfu2;
		  }
		}
		next;
	  }
	  if ((! defined($$infos{qfu})) && (($line =~ /^ ?(\d\d) (\d\d\d)/) || ($line =~ /^ ?(\d\d) ?[RL] (\d\d\d)/)))
	  {
		my ($qfu1, $qfu2) = ($1, $2);    # direction 1ere piste. Ex : "09 092"
		#print "$code;$qfu1;$qfu2\n";
		$$infos{qfu} = $qfu2;
	  }
	  if ((! defined($$infos{qfu})) && ($line =~ /^(\d\d\d) (\d\d\d)/))
	  {
		my ($qfu1, $qfu2) = ($1, $2);    # direction 1ere piste. Ex : "09 092"
		$$infos{qfu} = $qfu1;
	  }
	  if ((! defined($$infos{qfu})) && ($line =~ /^QFU (\d\d\d)/))
	  {
	    $$infos{qfu} = $1;
	  }
    
	  if ((! defined($$infos{dimension})) && (($line =~ /(\d+?) [xX] ?\d/) || ($line =~ /(\d+?) \(\d\) [xX] \d/)))
	  {
	    $$infos{dimension} = $1;
	  }
	  
	  if (! defined($$infos{nature}))
	  {  
	    $$infos{nature} = "herbe" if ($line =~ /Non revêtue/);
	    $$infos{nature} = "dur" if ($line =~ /Revêtue/);
	  }
	}
	last if (($deb_qfu) && (defined($$infos{qfu})) && (defined($$infos{dimension})) && (defined($$infos{nature})));
  }
  close FIC;
  
  my $frequence;
  if ((defined($$infos{AA})) && ($$infos{AA} ne "NIL"))
  {
	$frequence = $$infos{AA};
  }
  elsif ((defined($$infos{TWR})) && ($$infos{TWR} ne "NIL"))
  {
	$frequence = $$infos{TWR};
  }
  elsif ((defined($$infos{AFIS})) && ($$infos{AFIS} ne "NIL"))
  {
    $frequence = $$infos{AFIS};
  }
  elsif ((defined($$ADRef{frequence})) && ($$ADRef{frequence} ne ""))
  {
	$frequence = $$ADRef{frequence};
	print "$code. Frequence |$frequence| recuperee du fichier de reference\n" if ($verbose);
  }
  else
  {
	print "$code. Frequence pas trouvee, ni dans le PDF, ni dans le fichier de reference\n" if ($verbose);
  }
  if (defined($frequence))
  {
    $frequence =~ s/\.$//;    # il y a parfois un point finale en trop
    $$infos{frequence} = $frequence;
  }
  
  my $mess = "";
  foreach my $info ("qfu", "dimension", "nature")
  {
    if ((! defined($$infos{$info})) && (defined($$ADRef{$info})))    # on recupere du fuchier de reference
	{
	  if ($info eq "nature")
	  {
	    if (defined($cats{$$ADRef{nature}}))
		{
	      $$infos{nature} = $cats{$$ADRef{nature}};
		  $mess .= "$info : $$infos{$info}    ";
		}
	  }
	  else
	  {
	    if ($$ADRef{$info} ne "")
		{
	      $$infos{$info} = $$ADRef{$info} ;
		  $mess .= "$info : $$infos{$info}    ";
		}
	  }
	}
  }
  
  print "$code. Informations recuperees du fichier de reference : $mess\n" if (($verbose) && ($mess ne ""));
  
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
  $$infos{type} = "$$infos{cat} $$infos{type}";
  $$VACs{$code} = $infos;
  
  return $infos;
}
