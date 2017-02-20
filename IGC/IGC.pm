package IGC;

# traitments sur fichier IGC
#
# voir :
#   . http://carrier.csi.cam.ac.uk/forsterlewis/soaring/igc_file_format/
#   . http://carrier.csi.cam.ac.uk/forsterlewis/soaring/igc_file_format/igc_format_2008.html
#   . https://github.com/twpayne/igc2kmz/blob/master/igc2kmz/igc.py
#   . http://www.gpspassion.com/forumsen/topic.asp?TOPIC_ID=17661
#
# Ne lit que certains types de record
# Librairie très très partielle en terme de fonctionnalités ; a utiliser avec modération
#
#
# type A : Manufacturer code. Un seul enregistrement dans le fichier, c'est le premier. Les 3 premiers caractères sont le code constructeur. format libre
#---------------------------
#
# type H : Header. Différentes informations générales à l'IGC
#----------------
#
# type I : permet de spécifier le contenua de l'extension du format du record B. Un seul record I, après les records H
# -------------------------
# exemple : I023638FXA3940SIU : I,02,36,38,FXA,39,40,SIU
#  02 : 2 extensions
#  36, 38, FXA : le 1ere extension est le FXA, du 36eme au 38 eme caractere. FXA = Fix Accuracy : Estimated Position Error, en mètres
#  39,40,SIU : la seconde extention est le SIU, du 39eme au 40eme caractere. SIU = Satellites In Use
#
# type C : Task. Le circuit paramétré
# ----------------
# doit être après types H, I, J et avant type B
#   pour le moment, on ne decodera pas ces enregistrements.
#  . le premier donne la date et le time UTC de la déclaration, la date prévue du vol, le task-id, le nbre de 'turn points' (sans début et fin), et eventuellement du texte libre
#       C080915130551000000000002 : C,080915,130551,000000,0000,02
#  . Les enregistrements C suivants donnent les points prévus, le 1er étant le décollage et le dernier l'atterrissage
#                 latitude, longitude, description
#       C4800983N00635916EREMIREMONT GARE
#
# type B : basic tracklog record
# ------------------------------
# c'est celui qui nous intéresse le plus
# exemple : B1101355206343N00006198WA0058700558  (ce sont les infos minimum du type B. il peut y avoit des infos complémentaires après)
# B,110135,5206343N,00006198W,A,00587,00558
#
# B: record type is a basic tracklog record
# 110135: <time> tracklog entry was recorded at 11:01:35 i.e. just after 11am
# 5206343N: <lat> i.e. 52 degrees 06.343 minutes North
# 00006198W: <long> i.e. 000 degrees 06.198 minutes West
# A: <alt valid flag> confirming this record has a valid altitude value
# 00587: <altitude from pressure sensor>
# 00558: <altitude from GPS>
#
# type F : Satellite constellation
# --------------------------------
# enregistrement obligatoire
#   
# F160240 04 06 09 12 36 24 22 18 21 : F,060240,04,0609,1236,2422,1821
# 16h02mn40s - 4 satellites : 0609, 1236, 2422, 1821
#
# type E : Event
# --------------
# enregistrement d'évenements spécifiques
#   pour le moment, on ne decodera pas ces enregistrements
#
# type G : Scurity
# ----------------
# cheksum du message IGC, pour vérifier l'intégrité. C'est une 'signature' du fichier, pour assurer la vérité
#on ne décode pas ces enregistrements


use Data::Dumper;

use strict;

my %typeRecords =      # le type de record que l'on traite. read = fonction qui va traiter le read, ...
(
   "A" => { format => "array", read => \&_read_recordA } ,  # Manufacturer code
   "B" => { format => "array", read => \&_read_recordB } ,  # tracklog
   "H" => { format => "hash",  read => \&_read_recordH } ,  # Headers. format hash : on peut rechercher par la clé
   "I" => { format => "array", read => \&_read_recordI } ,  # spécification de l'extension du record B
   "F" => { format => "array", read => \&_read_recordF } ,   # Les satellites utilisés par le GPS
   "C" => { format => "array", read => \&_read_record_generic } ,  # Task. On ne fait pas de traitement dessus
   "E" => { format => "array", read => \&_read_record_generic } ,  # Events. On ne fait pas de traitement dessus
   "G" => { format => "array", read => \&_read_record_generic } ,  # Security. controle d'intégrité des données
   "Z" => { format => "array", read => \&_read_record_generic } ,  # Hors protocole. C'est la poubelle, ou y met ce qui ne va pas ailleurs
);
 
sub new {
  my $proto = shift;
  my %args =  @_;
  
  my $class =  ref($proto) || $proto;
  my $self = {};
  bless($self, $class);
  
  $self->{file} = $args{file} if (defined($args{file}));   # le fichier IGC a traiter
  &_initRecords($self);
    
  return $self;
}

# procedure interne, pour initialiser les structures d'enregistrement des traces igc
sub _initRecords
{
  my $self = shift;

  $self->{types}{all} = { nb => 0, values => []}; # tous les enregistrements du fichier IGC de type connus
  $self->{types}{A} = { nb => 0, values => [] };  # enregistrements de type A. 1 seul
  $self->{types}{B} = { nb => 0, values => []};   # les records de type B
  $self->{types}{H} = { nb => 0, values => [], hash => {}};   # les records de type H
  $self->{types}{I} = { nb => 0, values => [] }; # enregistrements de type I. Un seul
  $self->{types}{F} = { nb => 0, values => [] }; # enregistrements de type F
  $self->{types}{C} = { nb => 0, values => [] }; # enregistrements de type C
  $self->{types}{E} = { nb => 0, values => [] };
  $self->{types}{G} = { nb => 0, values => [] };
  $self->{types}{Z} = { nb => 0, values => [] }; # hors protocole. Permet de stocker les records inconnus
}

# recup du tabeau de tous les records
# arguments formels
#   . type : le type de record concerné, ou "all" pour tous. Par défaut, "all"
#   . hash : si différent de 0, retourne le hash, si c'est un type de format hash
sub getAllRecords
{
  my $self = shift;
  my %args =  (type => "all", hash => 0, @_);
  
  my $type = $args{type};
  my $with_hash = $args{hash};
  
  if (($with_hash == 0) || ($type eq "all"))
  {
    return $self->{types}{$type}{values};
  }
  
  return undef if ($typeRecords{$type}{format} ne "hash");
  return $self->{types}{$type}{hash};
}

# recuperation des enregistrements IGC, décodés
# un argument formel :
#   . type. facultatif. Le type de record concerné, ou "all" pour tous. Par défaut, "all"
sub getRecords
{
  my $self = shift;
  my %args =  (type => "all", @_);
  
  my $type = $args{type};
  
  return $self->{types}{$type}{values};
}

# recuperation d'un enregistrement IGC, décodés
# deux arguments formels :
#   . index. obligatoire. L'index du record recherché
#   . type. facultatif. Le type de record concerné, ou "all" pour tous. Par défaut, "all"
#
# retourne le record, ou undef si index est en dehors du tableau
sub getOneRecord
{
  my $self = shift;
  my %args =  (type => "all", @_);
  
  die "getOneRecord. Il faut au moins passer l'argument formel 'index'" unless(defined($args{index}));
  my $type = $args{type};
  my $index = $args{index};
  
  return undef if ($index >= $self->{types}{$type}{nb} + 1);
  return $self->{types}{$type}{values}[$index];
}


# recupération d'un record de type H, par sa clé
# la clé correspond aux 3 caractères à partir du 3eme. Par exemple, la clé pour la ligne suivante est : CID
# HFCIDCOMPETITIONID:DG
#
# par défaut, retourne la valeur de la clé. 
# 
# un argument 'classique' : la clé recherchée
# un argument formel :
#   . return : peu avoir les valeurs "value", "record", "raw"
#        value : par défaut. retourne la valeur de la clé.  
#        record : le hash contenant les informations du 'record'
#        raw : la ligne d'origine
#
# exemple, pour obtenir la date de l'enregistrement (JJMMAA) :
#  my $date = $igc->getHeaderByKey("DTE");
sub getHeaderByKey
{
  my $self = shift;
  my $key = shift;
  my %args =  ( @_ );
  
  my $return = $args{return};

  return undef unless(defined($self->{types}{H}{hash}{$key}));
  my $record = $self->{types}{H}{hash}{$key};
  return $record if ($return eq "record");
  return $$record{raw} if ($return eq "raw");
  return $$record{value};
}

  
# lecture du fichier igc
sub read
{
  my $self = shift;
  my %args =  @_;
  
  $self->{file} = $args{file} if (defined($args{file}));
  
  die "IGC.read : Il manque le nom de fichier" unless(defined($self->{file}));  
  die "IGC.read : unable to read fic $self->{file}" unless (open (FIC, "<$self->{file}"));
  
  &_initRecords($self);
  
  my $nbLines = 0;
  while (my $line = <FIC>)
  {
    $nbLines++;
	chomp($line);
	
	my $type = substr($line, 0, 1);
    $type = "Z" unless (defined($typeRecords{$type}));  # on triche, pour les records de types inconnus

	my $function = $typeRecords{$type}{read}; # la fonction qui traite la lecture de ce type de record
    next unless (defined($function));         # ne doit pas arriver
	
	my $result = &$function($self, $line);           # on appelle la fonction specifique a ce type de record
	unless(defined($result))
	{
	  die "IGC.read : Erreur ligne $nbLines :\n    $line\n";
	  next;
	}
	
	$$result{lineNumber} = $nbLines;
    $self->{types}{$type}{nb}++;
	my $values = $self->{types}{$type}{values};
	push(@$values, $result);
	
	if ($typeRecords{$type}{format} eq "hash")   # on veut aussi pouvoir acceder aux infos via un hash
	{
	  my $key = $$result{key};     # la clé du hash
	  my $hash = $self->{types}{$type}{hash};
	  $$hash{$key} = $result;
	}

	$type = "all";
    $self->{types}{$type}{nb}++;
	my $values = $self->{types}{$type}{values};
	push(@$values, $result);
  }
  
  close FIC;
}


# fonction interne, appelee par fonction read. lecture d'un record de type B
# on associe aux recors B le record F immédiatement précédent, ou undef s'il n'y en a pas 
#  (il devrait y en avoir au moins un, le record F est obligatoire, et le premier doit se trouvers avant les records B)
sub _read_recordB
{
  my $self = shift;
  my $line = shift;
  
  return undef unless ($line =~ /^B(\d{6})(\d{7}[NS])(\d{8}[EW])(.)(\d{5})(\d{5})(.*)/);

  my ($time, $lat, $long, $flag, $altSensor, $altGPS, $ext) = ($1, $2, $3, $4, $5, $6, $7);
  my $nbRecordF = $self->{types}{F}{nb};
  my $lastRecordF = $nbRecordF > 0 ? $self->{types}{F}{values}[$nbRecordF - 1] : undef; # le dernier record F rencontré
  my $alt = $altSensor eq "" ? $altGPS : $altSensor;
  $alt =~ s/^0*//;   # on retire les eventuels chiffres 0
  
  return {type => "B", time => $time, lat => $lat, long => $long, flag => $flag, altSensor => $altSensor, altGPS => $altGPS, alt => $alt, ext => $ext, lastRecordF => $lastRecordF, raw => $line };
}

# fonction interne, appelee par fonction read. lecture d'un record de type F
# F160240 04 06 09 12 36 24 22 18 21 : F,060240,04,0609,1236,2422,1821
# 16h02mn40s - 4 satellites : 0609, 1236, 2422, 1821

sub _read_recordF
{
  my $self = shift;
  my $line = shift;
  
  return undef unless ($line =~ /^F(\d{6})(.*)/);

  my ($time, $last) = ($1, $2);
  my $nbSats = 0;
  my $sats = "";
  if ($last =~ /^(\d\d)(.*)/)
  {
    $nbSats = $1;
	$sats = $2;
  }
  
  return {type => "F", time => $time, nbSats => $nbSats, sats => $sats, raw => $line };
}

# fonction interne, appelee par fonction read. lecture d'un record de type H (Header)
sub _read_recordH
{
  my $self = shift;
  my $line = shift;
  
  if ($line =~ /^H([FOP])(DTE)(\d{6})/)       # UTC date, format DDMMYY
  {
    my ($source, $key, $date) = ($1, $2, $3);
    return {type => "H", key => $key, source => $source, raw => $line, value => $date};
  }

  if ($line =~ /^H([FOP])(FXA)(\d+)/)       # precision, en metres
  {
    my ($source, $key, $accuracy) = ($1, $2, $3);
    return {type => "H", key => $key, source => $source, raw => $line, value => $accuracy};
  }

  if ($line =~ /^H([FOP])(\w{3})(.*?):(.*)/)       # autres headers
  {
    my ($source, $key, $ext_key, $value) = ($1, $2, $3, $4);
    return {type => "H", key => $key, source => $source, raw => $line, long_key => "H" . $source . $key . $ext_key, value => $value};
  }
  
  return undef;
}

  
# fonction interne, appelee par fonction read. lecture d'un record de type A
#un seul record de type A
sub _read_recordA
{
  my $self = shift;
  my $line = shift;
  
  return undef unless ($line =~ /^A(.*)/);

  my $value = $1;
  return undef if ($value eq "");
  
  return {type => "A", value => $value, raw => $line};
}

# fonction interne, appelee par fonction read. lecture d'un record de type I
# un seul record de type I
sub _read_recordI
{
  my $self = shift;
  my $line = shift;
  
  my @extends;      #les extensions
  return undef unless ($line =~ /^I(\d\d)(.*)/);
  
  my ($nbreExt, $last) = ($1, $2);
  for (my $ind = 0; $ind < $nbreExt; $ind++)   # parcours des extensions déclarées
  {
    return undef unless ($last =~ /(\d\d)(\d\d)(\w{3})(.*)/);
	my ($start, $end, $ext) = ($1, $2, $3);
	$last = $4;
	push(@extends, {ext => $ext, start => $start, end => $end});
  }
  
  return {type => "I", exts => \@extends, raw => $line };
}

# lecture d'un enregistrement sans traitement.
sub _read_record_generic
{
  my $self = shift;
  my $line = shift;
  
  my $type = substr($line, 0, 1);
  return {type => $type, raw => $line};
}

##################### computeNMEA ##############################
# calcule les trames MNEA a partir des records de type B
# peut recevoir un ensemble de parametres, qui seront passés à la fonction &NMEAfromIGC, 
#    voir les commentaires de cette fonction &NMEAfromIGC pour de l'info sur les paramètres
# sauf les paramètres suivants :
#   . output. facultatif. si présent, les trames NMEA seront écrites dans le fichier spécifié par ce paramètre
#   . format. facultatif. Format des trames NMEA dans le fichier output. valeurs possibles : "GGA", "RMC", "GGA_RMC"
#   . time. facultatif. Format "NOW", ou <HHMMSS>. Si présent, les trames NMEA débuteront à l'heure précisée ;
#              et l'heure des trames suivantes seront décalées de la même facon que le fichier IGC
#              par exemple, si time = "120000" et que l'heure des 3 premières trames IGC de type B est "130551", "130557", "130602",
#                 l'heure des trames NMEA corespondantes sera "120000", "200006", "200011"
#              Si valeur "NOW", l'heure de début sera l'heure du moment (en fait, HHMMSS)
# 
sub computeNMEA
{
  my $self = shift;
  my %args =  ( output => "", @_ );
  
  my $output = $args{output};
  my $format = $args{format};
  
  my $startSecond;   # l'heure de demarrage souhaitée des trames NMEA, en secondes
  
  if (defined($args{time}))
  {
    $startSecond = &UTC2seconds($args{time});
	die "computeNMEA. Le parametre 'time' n'est pas correct : $args{time}" if ($startSecond < 0);
  }
  
  my $firstRecord = $self->getOneRecord(index => 0, type => "B");   # preier record de type B
  return [] unless(defined($firstRecord));   # pas de records de type B
  
  my @NMEA = ();      # va contenir toutes les trames NMEA
  
  if ($output ne "")   # on veut ecrire dans un fichier
  {
    die "ouverture du fichier $output impossible" unless (open OUTPUT, ">$output");
  }
  
  my $firstSecond = &UTC2seconds($$firstRecord{time});  # secondes du premier record de type B
  my $deltaSeconds = $startSecond - $firstSecond;    # la différence de temps souhaitée, en secondes. Peut être négatif
  
  my $records = $self->{types}{B}{values};
  foreach my $record (@$records)    # tous les records de type B
  {
    if (defined($startSecond))     #on veut modifier l'heure des trames NMEA
	{
	  my $recordSecond = &UTC2seconds($$record{time});   # le time du record B, en secondes
	  my $newSecond = $recordSecond + $deltaSeconds;     # le time que l'on souhaite maintenant
	  $args{time} = &seconds2UTC($newSecond); # le nouveau time, en HHMMSS
	}
	my $res = &NMEAfromIGC($record, %args);
    push(@NMEA, $res);

	if ($output ne "")
	{
	  if (($format eq "GGA") || ($format eq "GGA_RMC") || ($format eq "RMC_GGA"))
	  {
	    print OUTPUT "$$res{GPGGA}\n";
	  }
	  if (($format eq "RMC") || ($format eq "GGA_RMC") || ($format eq "RMC_GGA"))
	  {
	    print OUTPUT "$$res{GPRMC}\n";
	  }
	}
  }
  close OUTPUT if ($output ne "");
  
  return \@NMEA;
}

##################### NMEAfromIGC ##############################
# calcul d'une trame NMEA a partir d'un record de type B
# parametres formels :
#  . time. facultatif. format : "HHMMSS" ou "HHMMSS.mmm". Si présent, écrit ce time dans la trame NMEA, au lieu de celle du record de type B
#  . fix. facultatif. Pour les trames GGA, indique le "fix quality". 1 par défaut
#                     . 0 : invalid. Ceci mettra le nbre de satellites et le HDOP à 0.
#                     . 1 : GPS. On recuperera le nombre de satellites dans la trame IGC de type "F" la plus proche. 
#                                Ou la valeur du parametre nbsats si le nbre de satellites IGC est inférieur à 4
#                                Si pas de trame F, ou si trame F ne contient pas de satellite et pas de parametre nbsats, on traite comme fix=0
#                     . 8 : simulation. On traite comme 0
#  . nbsats. facultatif. Force le nombre de satellites de la trame NMEA, si fix = 1 et que le nbre de satellites de l'IGC est inférieur à cette valeur
#  . hdop. facultatif. Pour les trames GGA, fixe le hdop si fix = 1. Si pas valué et pas satellites, mis à "0.0". par défaut : "10" (au pif)
#
# Format d'une trame NMEA GGA et RMC  (voir http://www.gpsinformation.org/dale/nmea.htm#GGA et #RMC)
#    Voir aussi http://www.gpspassion.com/forumsen/topic.asp?TOPIC_ID=17661
#
# GPGGA
#------
#exemple condor :
#      $GPGGA,120023.068,4843.8718,N,00610.7960,E,1,12,10,609.3,M,,,,,0000*0D
# $GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47
# 123519 : hhmmss. peut être suivi de millièmes de secondes : 123519.289
# 4807.038,N : latitude
# 01131.000,E : longitude
# 1 : "fix quality" : type de positionnement. 0=invalid, 1=GPS, ..., 8=simulation
# 08 : nombre de satellites
# 0.9 : HDOP : précision horizontale. Fonction du nombre de satellites, et de leur positionnement
# 545.4,M : altitude en mètres, au dessus du niveau de la mer
# 46.9,M : Height of geoid (mean sea level) above WGS84 ellipsoid (peut être laissée vide, ou 0.0,M)
# 2 champs vides : "time in seconds since last DGPS update" et "DGPS station ID number"
# *47 : le checksum de la trame. Commence par "*"
#
# GPRMC
# -----
# exemple condor :
#      $GPRMC,120023.068,A,4843.8718,N,00610.7960,E,48.54,270.00,,,,*19
#
# $GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A
# 123519 heure UTC. peut être suivi de millièmes de secondes : 123519.289
# A            Status A=active or V=Void.
# 4807.038,N   Latitude 48 deg 07.038' N
# 01131.000,E  Longitude 11 deg 31.000' E
# 022.4        Speed over the ground in knots
# 084.4        Track angle in degrees True
# 230394       Date - 23rd of March 1994
# 003.1,W      Magnetic Variation
# *6A          The checksum data, always begins with *

sub NMEAfromIGC
{
  my $record = shift;
  my %args =  (format => "RMC", fix => 1, hdop => "0.0", nbsats => 0, @_ );
  
  my $fix = $args{fix};
  my $nbsats = $args{nbsats};
  my $hdop = $args{hdop};
  my $time = $args{time};
  
  my $ref = ref $record;
  die "NMEAfromIGC. Le parametre doit etre une reference vers un hash" if ($ref ne "HASH");
  die "NMEAfromIGC. Le parametre doit etre un record IGC de type B" if ($$record{type} ne "B");
  
  my $HHutc = $$record{time} . ".000";
  $$record{lat} =~ /^(\d{4})(\d{3})(\w)/;
  my $latitude = $1 . "." . $2 . "," . $3;
  $$record{long} =~ /^(\d{5})(\d{3})(\w)/;
  my $longitude = $1 . "." . $2 . "," . $3;
  
  if ($fix == 1)   # positionnement de type GPS. On essair de recuperer les infos de satellites
  {
    my $recordF = defined($$record{lastRecordF}) ? $$record{lastRecordF} : undef;  # le dernier record F rencontré avant ce record B
	$nbsats = $$recordF{nbSats} if (defined($recordF) && ($$recordF{nbSats} > $nbsats));
	if ($nbsats > 0)
	{
	  $hdop = "10" if ($hdop eq "0.0");     # valeur arbitraire
	}
	else
	{
	  $fix = 0;     # invalid : on ne recupere pas d'infos de satellites
	}
  }

  if ($fix != 1)    # 0 (invalid, ou 8 (simulation"). On positionne le nbre de  satellites a 0
  {
    $nbsats = 0;
	$hdop = "0.0";
  }  
  
  $time = (($time =~ /^\d{6}$/) || ($time =~ /^\d{6}\.\d{3}/)) ? $time : $$record{time};    # time passé en parametre, ou time du record F

# ----  trame RMC ------
      #                   UTC     A=valid   Latitude       Longitude    vitesse sol    angle de route
  my $RMC = "\$GPRMC" . ",$time" . ",A" . ",$latitude" . ",$longitude" . ","         .  "," .
      #                 date   var. magn.
                        ","  .   ",";
  $RMC .= "*" . &checksumNMEA($RMC);    # on ajoute le checksum a la trame NMEA
  
# ----  trame GGA ------ 
#                          UTC        Latitude       Longitude       fix           hdop
  my $GGA = "\$GPGGA" . ",$time" . ",$latitude" . ",$longitude" . ",$fix" . "," . sprintf("%02d", $nbsats) . ",$hdop" .
#                         altitude AMSL              correction hauteur    vide, vide
                        ",$$record{alt}.0" . ",M" .   ",,"              . ",,";
  
  $GGA .= "*" . &checksumNMEA($GGA);    # on ajoute le checksum a la trame NMEA
  
  return { GPGGA => $GGA, GPRMC => $RMC};
}


# calcul du checksum d'une trame NMEA
# "The checksum field consists of a '*' and two hex digits representing an 8 bit exclusive OR of all characters between, but not including, the '$' and '*'"
sub checksumNMEA
{
  my $trame = shift;
  
  $trame =~ s/^\$//;       # le $ en tete de trame ne participe pas au calcul du checksum
  $trame =~ s/\*\d\d$//;   # on supprime un ancien checksum éventuel
  my $v = 0;
  $v ^= $_ for unpack 'C*', $trame;
  sprintf '%02X', $v;
}

# transfo d'une heure en format HHMMSS ou HHMMSS.mmm en secondes
# l'heure peut aussi être "NOW" ; dans ce cas, la fonction retourne le nombre de secondes depuis 00h00m00s
sub UTC2seconds
{
  my $time = shift;
  
  my $millis;
  
  if ($time eq "NOW")
  {
	my ($sec, $min, $hour) = localtime(time);
	my $seconds = ($hour * 3600) + ($min * 60) + $sec;
	return $seconds;
  }

  ($time, $millis) = ($1, $2) if ($time =~ /^(\d{6})\.(\d*)$/);
  
  return -1 unless($time =~ /^(\d\d)(\d\d)(\d\d)$/);
  my $seconds = ($1 * 3600) + ($2 * 60) + $3;
  
  if (defined($millis))
  {
    $seconds .= "." . $millis;
	return sprintf("%.3f", $seconds);
  }
  else
  {
    return $seconds;
  }
}

# transfo de secondes en heure HHMMSS ; si milliemes, celui-ci sera conservé
# si la parametre est "NOW", retourne l'heure courante
sub seconds2UTC
{
  my $seconds = shift;

  if ($seconds eq "NOW")
  {
	my ($sec, $min, $hour) = localtime(time);
	return sprintf("%02d%02d%02d", $hour, $min, $sec);
  }
  
  my $millis;
  ($seconds, $millis) = ($1, $2) if ($seconds =~ /^(\d*)\.(\d*)$/);
  
  return -1 if ($seconds < 1);
  return -1 if ($seconds > 3600 * 24);

  my $hh = int($seconds / 3600);
  my $mm = int(($seconds % 3600) / 60);
  my $ss = int((($seconds % 3600) % 60));
  my $time = sprintf("%02d%02d%02d", $hh, $mm, $ss); # le nouveau time, en HHMMSS
  if (defined($millis))
  {
    $millis .= "00";
	return $time . "." . substr($millis, 0, 3);
  }
  return $time;
}

  
1;
__END__
