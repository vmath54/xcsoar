#!/usr/bin/perl

# regeneration du fichier CUP de reference (FranceVacEtUlm.cup) a partir des infos provenant de basulm.csv et des fichiers PDF du SIA et des bases militaires
#
# les infos provenant de basulm.csv sont recupérées depuis le fichier listULMfromCSV.csv, issu de readBasulm.pl
# les infos provenant du SIA et des bases militaires sont recupérées depuis le fichier listVACfromPDF.csv, issu de getInfosFromVACfiles.pl
#
# on utilise également en entrée le fichier FranceVacEtUlm.cup pour :
#   - lister les ajouts ou retraits de terrains
#   - récupérer le nom "friendly" des terrains
#   - récupérer le département

# controle que la carte existe dans in repository local

use VAC;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $verbose = 0;           # a 1 pour avoir les infos de modifications
my $printNameNotMatch = 0; # a 1 pour avoir les noms qui ne matchent pas

my $ficREF      = "FranceVacEtUlm.cup";  # le fichier de reference. En lecture
my $ficOUT      = "FranceVacEtUlm_new.cup";  # le fichier généré
my $ficVAC      = "listVACfromPDF.csv";  # issu de getInfosFromVACfiles.pl
my $ficULM      = "listULMfromAPI.csv";  # issu de basulm

my %natures =
(
  "eau"    => 1,
  "herbe"  => 2,
  "neige"  => 3,
  "dur"    => 5,
);

my $onlyAD = "";        # Vide normalement. Sinon, ne traite que ce terrain, et on dump la structure
#my $onlyAD = "LF1457";

{
  my $REFs = &readRefenceCupFile($ficREF, onlyAD => $onlyAD);  # on recupere les infos du fichier CUP de référence
  print "Lecture fic reference : ", Dumper($REFs) if ($onlyAD ne "");
	
  &traiteInfosADs($ficVAC, $REFs, onlyAD => $onlyAD);          # prise en compte des infos provenant des terrains SIA ou militaire
  &traiteInfosADs($ficULM, $REFs, noADs => $VAC::noADs, onlyAD => $onlyAD); # prise en compte des infos provenant des terrains BASULM
  print "Lecture fichiers terrains : ", Dumper($REFs) if ($onlyAD ne "");
  
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
  
  my @attrs2compare = ("lat", "long", "elevation", "frequence", "dimension", "cat", "qfu", "comment");

  my $ADs = &readInfosADs($fic);         # infos provenant des terrains SIA / militaires ou BASULM
  
  foreach my $code (sort keys %$ADs)
  {
    next if (($onlyAD ne "") && ($code ne $onlyAD));
	next if (defined($noADs) && defined($$noADs{$code}));  # on ne veut pas certains terrains. Voir VAC.pm
	
	my $REF = $$REFs{$code};	
    my $AD = $$ADs{$code};
	my $cible = $$AD{cible};
	my $name = $$AD{name};	
		
	my $lat = &convertGPStoCUP($$AD{lat});   $$AD{lat} = $lat;
	my $long = &convertGPStoCUP($$AD{long}); $$AD{long} = $long;
	die "$code;$cible;$name;$$AD{lat};$$AD{long}; Probleme dans latitude ou longitude" if (($lat eq "") || ($long eq ""));
	
	my $frequence = $$AD{frequence} eq "" ? undef : sprintf("%.3f", $$AD{frequence});
	$$AD{frequence} = $frequence;
	
	my $nature = $natures{$$AD{nature}};
    $nature = 1 if (! defined($nature));
	$$AD{nature} = $nature;
	
	my $elevation = $$AD{elevation};
	if ($elevation eq "")
	{
	  if (defined($REF) && defined($$REF{elevation}))
	  {
	    $elevation = $$REF{elevation};
		print "WARNING. $code;$cible;$name. Altitude non trouvee ; recuperee dans fichier de ref : $elevation\n";
	  }
	  else
	  {
	    print "ERRROR. $code;$cible;$name. Altitude non trouvee ; il faudra rectifier manuellement dans fichier genere\n";
	  }
	}
	if ($elevation ne "")
	{
	  $elevation = sprintf("%.0f", $$AD{elevation} * 0.3048);
	  $$AD{elevation} = $elevation;
	}
	
    my $qfu = $$AD{qfu};
	$qfu =~s /^0*//;
	$$AD{qfu} = $qfu;
				  
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

	  my $line = &buildLineReferenceCupFile($AD);
      print "       $line\n";
	  
	  $$REFs{$code} = { found => "new", code => $code, cible => $cible, name => $name, shortName => $$AD{name}, lat => $lat, long => $long, elevation => $elevation, frequence => $frequence, dimension => $$AD{dimension}, nature => $nature, qfu => $$AD{qfu}, depart => $$AD{depart}, comment => $$AD{comment}  };
	  #print Dumper($AD);
	  #exit;
	  next;
	}
	
	if ($cible ne $$REF{cible})
	{
	  next if ($cible eq "basulm");    # on ne prend pas en compte basulm si terrain SIA ou MIL
	  print "WARNING. $code;$cible;$name; la cible initiale etait $$REF{cible}\n";
	  $$REF{cible} = $cible;
	}
	
	if (($printNameNotMatch) && (! &compareNames($name, $$REF{name})))
	{
	  printf ("%-6s;%-6s;NAME_NOT_MATCH : |%-30s| <- |%s|\n", $code, $cible, $$REF{name}, $name);
	}
	
	my $mess;
    foreach my $attr (@attrs2compare)
    {
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
