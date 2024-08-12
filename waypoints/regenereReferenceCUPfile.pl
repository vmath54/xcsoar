#!/usr/bin/perl

# regeneration du fichier CUP de reference (FranceVacEtUlm.cup) a partir des infos provenant de basulm.csv et des fichiers PDF du SIA et des bases militaires
#
# les infos provenant de basulm.csv sont recupérées depuis le fichier listULMfromCSV.csv, issu de getInfosFromApiBasulm.pl
# les infos provenant du SIA et des bases militaires sont recupérées depuis le fichier listVACfromPDF.csv, issu de getInfosFromVACfiles.pl
#
# on utilise également en entrée le fichier FranceVacEtUlm.cup pour :
#   - lister les ajouts ou retraits de terrains
#   - récupérer le nom "friendly" des terrains
#   - récupérer le département

# controle que la carte existe dans le repository local (./mil, ./vac, ./basulm)
#
# parametres acceptés :
#
# . -v ou --verbose : facultatif. Affiche les infos de modifications
# . -pn ou --printNameNotMatch : liste les noms de terrain qui ne matchent pas
# . -h ou --help : l'aide en ligne

use VAC;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $verbose;           # si valide, permet d'avoir les infos de modifications
my $printNameNotMatch; # si valide, liste les noms qui ne matchent pas

my $ficREF      = "FranceVacEtUlm.cup";  # le fichier de reference. En lecture
my $ficOUT      = "FranceVacEtUlm_new.cup";  # le fichier généré
my $ficVAC      = "listVACfromPDF.csv";  # issu de getInfosFromVACfiles.pl
my $ficULM      = "listULMfromAPI.csv";  # issu de basulm

my $onlyAD = "";        # Vide normalement. Sinon, ne traite que ce terrain, et on dump la structure
#my $onlyAD = "LF6321";

{
  my $help;
  my $ret = GetOptions
  ( 
    "v|verbose"            => \$verbose,
    "pn|printNameNotMatch" => \$printNameNotMatch,
    "h|help"               => \$help,
  );

  die "parametre incorrect" unless($ret);
  &syntaxe() if ($help);
  
  my $REFs = &readCupFile($ficREF, onlyAD => $onlyAD, ref => 1);  # on recupere les infos du fichier CUP de référence

  print "Lecture fic reference : ", Dumper($REFs) if ($onlyAD ne "");
	
  &traiteInfosADs($ficVAC, $REFs, onlyAD => $onlyAD);          # prise en compte des infos provenant des terrains SIA ou militaire
  &traiteInfosADs($ficULM, $REFs, noADs => $VAC::noADs, onlyAD => $onlyAD); # prise en compte des infos provenant des terrains BASULM
  print "Lecture infos generees : ", Dumper($REFs) if ($onlyAD ne "");
  
  &delOldADs($REFs);                                           # suppression des fiches qui n'ont pas été renouvelées
  
  my $nbre = scalar (keys %$REFs);
  print "$nbre fiches generees\n";

  #&writeRefenceCupFile($REFs);  # on ecrit le fichier en stdout
  &writeRefenceCupFile($REFs, fic => $ficOUT);  # ou dans un fichier
}

################# suppression eventuelle des fiches qui ne sont plus dans les bases SIA, militaires ou BASULM
sub delOldADs
{
  my $REFs = shift;
  
  foreach my $code (sort keys %$REFs)
  {
    my $REF = $$REFs{$code};
	unless (defined($$REF{found}))
	{
	  print "WARNING. $code;$$REF{cible};$$REF{name}; Ce terrain n'existe plus dans les nouvelles bases. Il va être supprimé\n";
	  delete $$REFs{$code};
	}
  }
}

############## traitement des infos provenant des terrains SIA ou militaire (vac) ou BASULM (baasulm)
sub traiteInfosADs
{
  my $fic = shift;
  my $REFs = shift;
  my %args = (@_);
  
  my $onlyAD = $args{onlyAD};
  my $noADs = $args{noADs};
  
  my @attrs2compare = ("lat", "lon", "elev", "freq", "rwlen", "rwwidth", "style", "rwdir", "desc");

  my $ADs = &readInfosADs($fic);         # infos provenant des terrains SIA / militaires ou BASULM
  print "Lecture infos en lecture : ", Dumper($$ADs{$onlyAD}) if ($onlyAD ne "");
  
  foreach my $code (sort keys %$ADs)
  {
    next if (($onlyAD ne "") && ($code ne $onlyAD));
	next if (defined($noADs) && defined($$noADs{$code}));  # on ne veut pas certains terrains. Voir VAC.pm
	
	my $REF = $$REFs{$code};	
    my $AD = $$ADs{$code};
	my $cible = $$AD{cible};
	my $name = $$AD{name};	
		
	my $lat = &convertGPStoCUP($$AD{lat});   $$AD{lat} = $lat;
	my $lon = &convertGPStoCUP($$AD{lon}); $$AD{lon} = $lon;
	die "$code;$cible;$name;$$AD{lat};$$AD{lon}; Probleme dans latitude ou longitude" if (($lat eq "") || ($lon eq ""));
	
	my $freq = $$AD{freq} eq "" ? undef : sprintf("%.3f", $$AD{freq});
	$$AD{freq} = $freq;
	
	my $elev = $$AD{elev};
	if ($elev eq "")
	{
	  if (defined($REF) && defined($$REF{elev}))
	  {
	    $elev = $$REF{elev};
		print "WARNING. $code;$cible;$name. Altitude non trouvee ; recuperee dans fichier de ref : $elev\n";
	  }
	  else
	  {
	    print "ERRROR. $code;$cible;$name. Altitude non trouvee ; il faudra rectifier manuellement dans fichier genere\n";
	  }
	}
	if ($elev ne "")
	{
	  $elev = sprintf("%.0f", $$AD{elev} * 0.3048);
	  $$AD{elev} = $elev;
	}
	
    my $rwdir = $$AD{rwdir};
	$rwdir =~s /^0*//;
	$$AD{rwdir} = $rwdir;
	
	################ Dans cette section, on cree un nouveau terrain #####################
	unless(defined($REF))
	{
	  print "WARNING. $code;$cible;$name; est dans le fichier '$cible' mais n'est pas dans le fichier de référence.\n";
	  print "    Il faudra verifier et eventuellement adapter les infos dans le fichier généré.\n";
	  	  
	  if ($cible eq "basulm")
	  {
	    if ($$AD{code} =~ /^LF(\d\d)\d\d$/)
		{
		  $$AD{depart} = $1;
		}
		else
		{
		  $$AD{depart} = "";
		}
	  }
	 	  
	  $$AD{desc} = $name;
	  my $line = &buildLineReferenceCupFile($AD);
      print "       $line\n";
	  
	  $$REFs{$code} = { found => "new", code => $code, cible => $cible, name => $name, lat => $lat, lon => $lon, elev => $elev, freq => $freq, rwlen => $$AD{rwlen}, rwwidth => $$AD{rwwidth}, style =>$$AD{style}, rwdir => $$AD{rwdir}, desc => $$AD{desc}, depart => $$AD{depart}, cat => $$AD{cat} };
	  #print Dumper($AD); exit;
	  next;
	}
	################ Fin de section de creation d'un nouveau terrain #####################
	
	if ($cible ne $$REF{cible})
	{
	  next if ($cible eq "basulm");    # on ne prend pas en compte basulm si terrain SIA ou MIL
	  print "WARNING. $code;$cible;$name; la cible initiale etait $$REF{cible}\n";
	  $$REF{cible} = $cible;
	}
	
	if (($printNameNotMatch) && (! &compareNames($name, $$REF{name})))
	{
	  printf ("%-6s;%-6s;NAME_NOT_MATCH : |%-30s <- |%s|\n", $code, $cible, $$REF{name} . "|", $name);
	}
	
	$$AD{desc} = $$REF{desc};
	
	my $mess;
    foreach my $attr (@attrs2compare)
    {
	  #print "$attr : |$$REF{$attr}| <- |$$AD{$attr}|\n";
	  if ($$REF{$attr} ne ($$AD{$attr}))
	  {
	    my $attrUC = uc($attr);
	    $mess .= "$attrUC : |$$REF{$attr}| <- |$$AD{$attr}|  ";
		$$REF{$attr} = $$AD{$attr};
	  }
	}
	if ($mess ne "")
	{
	  print "$code;$cible;$name; mise a jour de $mess\n" if ($verbose);
	  $$REF{found} = "modify";
	}
	else
	{
	  $$REF{found} = "OK";
	}
  }
}

sub syntaxe
{
  print "regenereReferenceCUPfile.pl\n";
  print "Ce script permet de generer le fichier FranceVacEtUlm_new.cup à partir des fichiers FranceVacEtUlm.cup, listULMfromCSV.csv et listVACfromPDF.csv\n\n";
  print "les parametres sont :\n";
  print " . -v ou --verbose : facultatif. Affiche les infos de modifications\n";
  print " . -pn ou --printNameNotMatch : liste les noms de terrain qui ne matchent pas\n";
  print " . -h ou --help : l'aide en ligne\n";
  exit;
}