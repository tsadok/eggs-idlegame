#!/usr/bin/perl
# -*- cperl -*-

use strict;
use utf8;
use open ':encoding(UTF-8)';
use open ":std";
#use bignum;
use DateTime;
use Term::Size;
use Term::ReadKey;
use Time::HiRes qw(gettimeofday tv_interval);
use Term::ANSIColor;
use File::Spec::Functions qw(catfile);
use File::HomeDir;
use Math::Tau;
use Carp;
#use Profile::Log;

our $reset = chr(27) . qq{[0m};
our ($screen, $xmax, $ymax);
our ($wfocus, $wcount, @widget, %bigtextfont, @namedcolor);
our (%option, $egggamelogfile, $widgetlogfile, $colorlogfile, $screenlogfile);

require "./paths.pl";
require "./logging.pl";
require "./widgets.pl";

my $version = "0.3.2 alpha";
binmode(STDOUT, ":utf8");

#################################################################################################
#################################################################################################
###
###                                        O P T I O N S :
###
#################################################################################################
#################################################################################################

my @clropt = map {  +{ key => $$_{key}, value => $$_{name}, name => $$_{name}, },
                  } grep { $$_{key} } @namedcolor;
my @option = ( +{ short    => "-",
                  default  => undef,
                  true     => "true",
                  name     => "disable_shortops",
                  desc     => "When processing command-line arguments, ignore 'short-form' (hyphen-letter) options",
                  save     => "none",
                  # This is just in case somebody needs to do something bizarre,
                  # like specify a filename that starts with a hyphen, on the
                  # command line.  You can safely just ignore this option.
                },
               +{ name     => "localtimezone",
                  save     => "user",
                  default  => "America/New_York",
                  enum     => [ +{ key => "u", value => "UTC",                  name => "UTC", },
                                +{ key => "e", value => "America/New_York",     name => "Eastern", },
                                +{ key => "c", value => "America/Chicago",      name => "Central", },
                                +{ key => "m", value => "America/Denver",       name => "Mountain", },
                                +{ key => "p", value => "America/Los_Angeles",  name => "Pacific", },
                                +{ key => "k", value => "America/Anchorage",    name => "Alaska", },
                                +{ key => "q", value => "Europe/London",        name => "Britain", },
                                +{ key => "r", value => "Europe/Paris",         name => "Europe (CET)", },
                                +{ key => "s", value => "Europe/Helsinki",      name => "Europe (East)", },
                                +{ key => "t", value => "Europe/Moscow",        name => "Moscow", },
                                +{ key => "z", value => "Australia/Brisbane",   name => "Oz", },
                                +{ key => "n", value => "Pacific/Auckland",     name => "New Zealand", },
                              ],
                },
               +{ name    => "autosave",
                  default => "annually",
                  true    => "monthly",
                  desc    => "Automatically save your progress every so often.",
                  key     => "a",
                  save    => "user,game",
                  enum    => [ +{ key => "o", value => "", name => "off (F4 to save)", },
                               +{ key => "m", value => "monthly", name => "monthly",   },
                               +{ key => "a", value => "annually", name => "annually", },
                             ],
                },
               +{ name    => "colordepth",
                  default => 8,
                  true    => 24,
                  desc    => "Bit depth for terminal colors.",
                  key     => "c",
                  save    => "user",
                  enum    => [+{key => "m", value =>  1, name => "Mono/bw"},
                              +{key => "3", value =>  3, name => "Basic ANSI"},
                              +{key => "4", value =>  4, name => "Full ANSI"},
                              +{key => "8", value =>  8, name => "256-color"},
                              +{key => "t", value => 24, name => "TrueColor"},],
                },
               +{ name    => "focusbgcolor",
                  default => "blue",
                  desc    => "Background color used to indicate the currently focused frame.",
                  key     => "f",
                  save    => "user",
                  enum    => [+{ key => "v", value => "",        name => "various" },
                              @clropt,
                             ],
                },
               +{ name    => "delay",
                  short   => "d",
                  default => 1,
                  save    => "user",
                  regex   => qr/(\d+[.]?\d*)/,
                  desc    => "Number of seconds to let pass between iterations.  Does not have to be an integer.",
                },
               +{ name    => "xmax",
                  short   => "x",
                  default => 0,
                  desc    => "One less than the width of your terminal, in characters.  0 means use detected size.",
                  save     => "none",
                },
               +{ name    => "ymax",
                  short   => "y",
                  default => 0,
                  desc    => "One less than the height of your terminal, in characters.  0 means use detected size.",
                  save     => "none",
                },
               +{ name    => "nohome",
                  default => 0,
                  true    => 1,
                  enum    => [ +{ key => "y", value => "true", name => "yes" },
                               +{ key => "n", value => "",     name => "no", },
                             ],
                  save    => "user",
                  desc    => "Instead of returning to home position before redrawing, just scroll the previous screenful out of the way.",
                },
               +{ name    => "fullrect",
                  default => 0,
                  true    => 1,
                  save    => "user",
                  desc    => "Go ahead and fill in the character in the very bottom-right corner of the screen.  (On some terminals, this can cause unwanted scrolling.)",
                  enum    => [ +{ key => "y", value => "true", name => "yes" },
                               +{ key => "n", value => "",     name => "no", },
                             ],
                },
               +{ name    => "pauseonngp",
                  desc    => "Automatically pause the game when a new heir inherits.",
                  key     => "p",
                  default => "",
                  true    => "true",
                  save    => "user,game",
                  enum    => [ +{ key => "y", value => "true", name => "yes" },
                               +{ key => "n", value => "",     name => "no", },
                             ],
                },
               +{ name    => "sellchickens",
                  desc    => "How to sell off spare chickens when necessary.",
                  key     => "s",
                  enum    => [+{ key => "b", value => "b", name => "best price",}, # Same in practice as good home, at least for now
                              +{ key => "g", value => "g", name => "good home",},
                              +{ key => "m", value => "m", name => "meat only",}, # Desirable once you start genetic engineering, as it protects trade secrets.
                             ],
                  default => "b",
                  save    => "game",
                },
               +{ name    => "sellbonds",
                  desc    => "When to automatically sell off bonds to cover purchases.",
                  key     => "b",
                  enum    => [+{ key => "n", value => 0, name => "never",},
                              +{ key => "m", value => 1, name => "mature bonds only",},
                              +{ key => "a", value => 2, name => "always",},
                             ],
                  default => 1,
                  save    => "game",
                },
               +{ name    => "savefile",
                  default => catfile(get_config_dir(), "eggs.save"),
                  desc    => "Path and file name of the saved-game file.",
                  save    => "none",
                },
               +{ name    => "optionsfile",
                  default => catfile(get_config_dir(), "eggs.cfg"),
                  desc    => "Path and file name of the user's options/configuration file.",
                  save    => "none",
                },
               +{ name    => "debug",
                  default => 0,
                  true    => 1,
                  save    => "none",
                },
               #+{ name    => "writepricelist",
               #   default => 0,
               #   true    => 1,
               #   save    => "none",
               # },
               +{ name    => "channelcolor_story",
                  desc    => "Color for messages about the game's over-arching story and your character's life.",
                  default => "white",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_occasion",
                  desc    => "Color for messages about events that occur in the game's world.",
                  default => "yellow",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_credit",
                  desc    => "Color for messages about your credit rating.",
                  default => "spring-green",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_stock",
                  desc    => "Color for messages about the stock market.",
                  default => "spring-green",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_actioncancel",
                  desc    => "Color for messages about things you tried to do that didn't work out.",
                  default => "orange",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetloss",
                  desc    => "Color for messages about business losses you incur.",
                  default => "red",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetgain",
                  desc    => "Color for messages about things your business gains.",
                  default => "green",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetneed",
                  desc    => "Color for messages about things your business needs in order to grow.",
                  default => "orange",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_budgetaction",
                  desc    => "Color for messages about the results of your budget choices.",
                  default => "azure",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_assetsold",
                  desc    => "Color for messages about things your business sells; this includes things you have to sell for lack of space.",
                  default => "cyan",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_meta",
                  desc    => "Color for messages about matters external to the game itself (e.g., save/restore).",
                  default => "indigo",
                  save    => "user",
                  enum    => [ @clropt ],
                },
               +{ name    => "channelcolor_bug",
                  desc    => "Color for messages about programming errors you encounter in the game's implementation.  With any luck, maybe the chickens will eat all the bugs, and you'll never see these messages.  We can hope.",
                  default => "magenta",
                  save    => "user",
                  enum    => [ @clropt ],
                },
             );
%option = map { $$_{name} => $$_{default} } @option;
loadoptions(\%option);
debuglog("options: " . Dumper(\%option));

my @cmda = @ARGV; while (scalar @cmda) {
  my $x = shift @cmda;
  my $prevopt = undef;
  if (($x eq "--") and not $option{disable_shortops}) {
    $option{disable_shortops} = "true";
  } elsif ($x =~ /^-(\w+)$/ and not $option{disable_shortops}) {
    for my $f (split //, $1) {
      my ($o) = grep { $$_{short} eq $f } @option;
      if ($o) {
        $option{$$o{name}} = $option{$$o{true}};
        $prevopt = $$o{name};
      } else {
        die "Unrecognized command-line option, -$f";
      }}
  } elsif ($x =~ /^--(\w+)=(.*)/) {
    my ($n, $v) = ($1, $2);
    my ($o) = grep { $$_{name} eq $n } @option;
    if ($o) {
      $option{$$o{name}} = $v;
      $prevopt = undef;
    } else {
      die "Unrecognized command-line option, --$n";
    }
  } elsif ($x =~ /^--(\w+)$/) {
    my ($n) = ($1);
    my ($o) = grep { $$_{name} eq $n } @option;
    if ($o) {
      $option{$$o{name}} = $$o{true};
      $prevopt = $$o{name};
    } else {
      die "Unrecognized command-line option, --$n";
    }
  } elsif ($prevopt) {
    $option{$prevopt} = $x;
    $prevopt = undef;
  } else {
    die "Did not understand command-line option: $x";
  }
}

#################################################################################################
#################################################################################################
###
###                                    I N I T I A L I Z E :
###
#################################################################################################
#################################################################################################

my ($wbg, $wtopbar, $wcashflow, $wmessages, $wassets, $wbudget, $wbuy, $wsettings,
    $wgameclock, $wrealclock, $wordkey, $wticker);
my ($buyitem, $buystock, $setting, $budgetitem, $debughint);
my ($breedlvl, $genlvl, $genleak, $gamephase) = (1, 1, 1, 1);
# 64-bit maxint is 9,223,372,036,854,775,807 and we don't want to get too close to that.
# for comparison:    9223372036854775807;
my $investcashover =  100000000000000000;
my $defaultbondamt =   15000000000000000;
my $loanamount     =       1000000000000;

# Game state arrays:
my (@message, @messageline, @extantplace, @world, @nation, @province, @county);
# Arrays that are used to cache function-specific data across calls for perf reasons:
my (@rpw, @county_suffix, @city_prefix, @city_suffix, @placeword_suffix);
my @commonplacename = common_placenames();
my @commonsurname   = common_surnames();


my @relative = (["favourite uncle",  "he",  "his"],
                ["sainted aunt",     "she", "her"],
                ["grandfather",      "he",  "his"],
                ["grandmother",      "she", "her"],
                ((50 > rand 100) ? ["godfather", "he",  "his"] : ["godmother", "she", "her"]),
                (map {
                  ((50 > rand 100) ? [$_, "he", "his"] : [$_, "she", "her"]),
                } ("boss", "wealthy friend", "elderly neighbor", "second cousin", "English teacher", "classmate",
                   ((90 > rand 100) ? "secret admirer" : "creepy stalker"),
                   ((65 > rand 100) ? "grand" : "") . ((50 > rand 100) ? "father" : "mother") . "'s best friend",)),
                ["pastor",           "he",  "his"],
               );
#use Data::Dumper; print Dumper(+{ relative => \@relative }); exit 0;

if ($option{debug}) {
  for my $lf ($widgetlogfile, $colorlogfile, $egggamelogfile) {
    my $msg = qq[*************** Starting Egg Game $version ($0) [$$] ***************];
    if ($option{clearlogs}) {
      overwritelogfile($lf, $msg);
    } else {
      sendtologfile($lf, $msg);
    }}}

my @industry = stock_market_industries();
my %cashflow;
my %globalkeybinding = global_key_bindings();
my $inputprefix = "";
my ($now, $date); eval {
  $now  = DateTime->now( time_zone => ($option{localtimezone} || "UTC") );
  $date = DateTime->new( year      => 1970,
                         month     => 1,
                         day       => 1,
                         hour      => 6,
                         time_zone => ($option{localtimezone} || "UTC"),
                       );
};
croak "DateTime problems" if not ref $now;
croak "DateTime problems" if not ref $date;
my ($cash, $debt, $creditrating, $maxcreditrating, $primerate,
    $runstarted, $ngpeta, $birthdate,
    $paused);
$cash = $debt = $creditrating = $maxcreditrating = 0;
$primerate = 2.5;
my (%buyqtty, %budget, %asset, %windowitem, %stock, @bond);

END { ReadMode 0; };
ReadMode 3;
$|=1;

debuglog("Started game session " . $now->ymd() . " at " . $now->hms()) if $option{debug};

%buyqtty = ( 1 => +{ id     => 1,
                     key    => "o",
                     name   => "one",
                     number => 1,
                     pmult  => 1,
                   },
             dose => +{ id     => "dose",
                        key    => "o",
                        name   => "one dose",
                        number => 1,
                        pmult  => 1,
                      },
             10 => +{ id     => 10,
                      key    => "t",
                      name   => "ten",
                      number => 10,
                      pmult  => 10,
                    },
             12 => +{ id     => 12,
                      key    => "d",
                      name   => "dozen",
                      number => 12,
                      pmult  => 11,
                    },
             dozendoses => +{ id     => "dozendoses",
                              key    => "d",
                              name   => "dozen doses",
                              number => 12,
                              pmult  => 11,
                            },
             100 => +{ id     => 100,
                       key    => "h",
                       name   => "hundred",
                       number => 100,
                       pmult  => 100,
                     },
             1000 => +{ id     => 1000,
                        key    => "k",
                        name   => "thousand",
                        number => 1000,
                        pmult  => 1000,
                      },
             25000 => +{ id     => 25000,
                         key    => "i",
                         name   => "25k",
                         number => 25000,
                         pmult  => 25000,
                       },
             250000 => +{ id     => 250000,
                          key    => "j",
                          name   => "250k",
                          number => 250000,
                          pmult  => 250000,
                        },
             5000000 => +{ id     => 5000000,
                           key    => "l",
                           name   => "5m",
                           number => 5000000,
                           pmult  => 5000000,
                         },
             hundmil => +{ id     => "hundmil",
                           key    => "m",
                           name   => "100m",
                           number => 100000000,
                           pmult  => 100000000,
                         },
             billion => +{ id     => "billion",
                           key    => "b",
                           name   => "billion",
                           number => 1000000000,
                           pmult  => 1000000000,
                         },
             "25b"  => +{ id     => "25b",
                          key    => "n",
                          name   => "25 billion",
                          number => 25000000000,
                          pmult  => 25000000000,
                        },
             "250b" => +{ id     => "250b",
                          key    => "p",
                          name   => "250 billion",
                          number => 250000000000,
                          pmult  => 250000000000,
                        },
             # In asciibetical order, the decimal-based letter keys:
             # a - asneeded
             # b - billion
             # c - cancel
             # h - hundred (100)
             # i - 25k (25 thousand)
             # j - 250k (250 thousand)
             # k - thousand (1000)
             # l - 5 million
             # m - hundred million
             # n - 25b (25 billion)
             # o - one (1)
             # p - 250b (250 billion)
             # q - quadrillion (not yet implemented)
             # r - hundred trillion (not yet implemented)
             # s - 5 trillion (not yet implemented)
             # t - ten (10)
             # u - 25 quadrillion (not yet implemented)
             # v - 250 quadrillion (not yet implemented)
             # w - 5 quintillion (not yet implemented)
             144 => +{ id     => 144,
                       key    => "g",
                       name   => "gross",
                       number => 144,
                       pmult  => 100,
                     },
             1728 => +{ id     => 1728,
                        key    => "l",
                        name   => "lot (great gross)",
                        number => 1728,
                        pmult  => 1000,
                      },
             faireu => +{ id     => "faireu",
                          number => 20736,
                          pmult  => 10000,
                          name   => "faireu",
                          key    => "f",
                       },
             eaurie => +{ id     => "eaurie",
                          number => 248832,
                          pmult  => 100000,
                          name   => "eaurie",
                          key    => "e",
                        },
             passel => +{ id     => "passel",
                          number => 2985984,
                          pmult  => 1000000,
                          name   => "passel (greater gross)",
                          key    => "p",
                        },
             clutch => +{ id     => "clutch",
                          number => 35831808,
                          pmult  => 10000000,
                          name   => "clutch",
                          key    => "h",
                        },
             batallion => +{ id     => "batallion",
                             number => 429981696,
                             pmult  => 100000000,
                             name   => "batallion",
                             key    => "b",
                           },
             army => +{ id     => "army",
                        number => 5159780352,
                        pmult  => 1000000000,
                        name   => "army",
                        key    => "y",
                      },
             myriad => +{ id     => "myriad",
                          number => 743008370688,
                          pmult  => 100000000000,
                          name   => "myriad",
                          key    => "m",
                        },
             # Man, it's a good thing nobody uses 32-bit systems any more.  I think I want a 256-bit system.
             klatch => +{ id     => "klatch",
                          number => 106993205379072,
                          pmult  => 100000000000000,
                          name   => "klatch",
                          key    => "k",
                        },
             #jankette => +{ id     => "jankette",
             #               number => 15407021574586368,
             #               name   => "jankette",
             #               key    => "j",
             #               pmult  => 10000000000000000,
             #             },
             # In alphabetical order, the dozen-based letters:
             # a - asneeded
             # b - batallion (12 clutches)
             # c - cancel
             # d - dozen
             # e - eaurie (12 faireu)
             # f - faireu (12 lots)
             # g - gross (12 dozen)
             # h - clutch (12 passels)
             # i -
             # j - jankette (144 klatches)
             # k - klatch (144 myriad)
             # l - lot (12 gross)
             # m - myriad (144 armies)
             # n -
             # o - one (1)
             # p - passel (12 eaurie)
             # q -
             # r -
             # s -
             # t - too many
             # u -
             # v -
             # w -
             # x -
             # y - army (12 batallions)
             # z -
             feedbag => +{ id     => "feedbag",
                           key    => "b",
                           name   => "bag",
                           pmult  => 1, # feed prices are per-bag, of course
                           number => 150,
                           # A bag of feed feeds one adult chicken for 150 days.
                           # Chicks eat less.
                         },
             feedpallet => +{ id     => "feedpallet",
                              key    => "p",
                              name   => "pallet",
                              pmult  => 20,
                              number => 3750,
                            },
             feedtruck => +{ id      => "feedtruck",
                             key     => "t",
                             name    => "truckload",
                             pmult   => 180,
                             number  => 45000,
                           },
             feedwarehouse => +{ id     => "feedwarehouse",
                                 key    => "w",
                                 name   => "warehouse",
                                 pmult  => 5000,
                                 number => 2250000,
                               },
             asneeded_feed => +{ id         => "asneeded_feed",
                                 key        => "a",
                                 name       => "as needed",
                                 number     => "asneeded",
                                 price      => "?",
                                 unlockqtty => 50000,
                               },
             asneeded => +{ id         => "asneeded",
                            key        => "a",
                            name       => "as needed",
                            number     => "asneeded",
                            price      => "?",
                            unlockqtty => 1728,
                          },
             cancel => +{ id         => "cancel",
                          key        => "c",
                          name       => "cancel",
                          number     => "cancel",
                          hilight    => "orange",
                          fg         => "yellow",
                          unlockqtty => "0 but true",
                        },
             countylicense => +{ id        => "countylicense",
                                 key       => "a",
                                 name      => "county",
                                 placetype => \@county,
                                 generate  => sub { generate_county(@_), },
                                 value     => 125000000,
                               },
             provincelicense => +{ id        => "provincelicense",
                                   key       => "p",
                                   name      => "province",
                                   placetype => \@province,
                                   generate  => sub { generate_province(@_), },
                                   value     => 2500000000,
                                 },
             nationlicense => +{ id        => "nationlicense",
                                 key       => "n",
                                 name      => "nation",
                                 placetype => \@nation,
                                 generate  => sub { generate_nation(@_), },
                                 value     => 250000000000,
                               },
             worldlicense => +{ id        => "worldlicense",
                                key       => "w",
                                name      => "world",
                                placetype => \@world,
                                generate  => sub { generate_world(@_), },
                                value     => 25000000000000000,
                              },
           );
my @pctopt = map { my ($pct, $key) = @$_;
                   +{ name  => $pct . '%',
                      key   => $key,
                      pct   => $pct,
                    }
                 } ((map { [ $_ => "$_" ] } 1 .. 6, 8),
                    ([ 10 => "t" ], [ 12 => "d" ], [ 15 => "f" ], [ 18 => "e" ]));

%budget = ( medexam => +{ id    => "medexam",
                          key   => "m",
                          name  => "medical examinations",
                          desc  => "Have a veterinarian examine your chickens.",
                          sort  => 1,
                          value => "off",
                          enum  => +[ +{ name         => "off",
                                         key          => "o",
                                         timesperyear => 0,
                                       },
                                      +{ name         => "yearly",
                                         key          => "y",
                                         timesperyear => 1,
                                       },
                                      +{ name         => "quarterly",
                                         key          => "q",
                                         timesperyear => 4,
                                       },
                                      +{ name         => "monthly",
                                         key          => "m",
                                         timesperyear => 12,
                                       },
                                    ],
                          budget => sub {
                            my ($foo) = @_;
                            $foo ||= $budget{medexam}{value};
                            my ($val) = grep { $$_{name} eq $foo } @{$budget{medexam}{enum}};
                            my $numofchickens = $asset{hen}{qtty} + $asset{rooster}{qtty} + $asset{chick}{qtty};
                            my $peryear = 300 * $$val{timesperyear} * $numofchickens;
                            # Budget is monthly, so that's 1/12th the annual, on average.
                            return int($peryear / 12);
                          },
                        },
            breeding => +{ id    => "breeding",
                           key   => "b",
                           name  => "breeding program",
                           desc  => "Devote a portion of your profits to breeding better chickens.",
                           sort  => 5,
                           value => 0,
                           enum  => +[ @pctopt ],
                           budget => sub {
                             my ($foo) = @_;
                             $foo ||= $budget{breeding}{value};
                             return $foo;
                           },
                         },
            genetics => +{ id     => "genetics",
                           key    => "g",
                           name   => "genetics research",
                           desc   => "Hire a geneticist to improve your chickens.",
                           sort   => 6,
                           value  => 0,
                           enum  => +[ @pctopt ],
                           unlock => 99999999,
                           budget => sub {
                             my ($foo) = @_;
                             $foo ||= $budget{genetics}{value};
                             return $foo;
                           },
                         },
            debtreduction => +{ id       => "debtreduction",
                                key      => "d",
                                name     => "debt reduction",
                                desc     => "Try to pay down the principal on your loans, if you have loans.  If you don't have loans, this setting costs you nothing and does nothing.",
                                sort     => 12,
                                value    => 0,
                                progress => 0,
                                enum     => +[ @pctopt ],
                                budget   => sub {
                                  my ($foo) = @_;
                                  $foo ||= $budget{debtreduction}{value};
                                  return $foo;
                                },
                                gain     => sub {
                                  my ($amt) = @_;
                                  if ($debt > 0) {
                                    $budget{debtreduction}{progress} += $amt;
                                    $cash -= $amt; # It's _set aside_
                                    if ($budget{debtreduction}{progress} >= $loanamount) {
                                      my $payloans = int($budget{debtreduction}{progress} / $loanamount);
                                      $payloans = $debt if $payloans > $debt;
                                      # Un-set it aside, because we're about to use it:
                                      $budget{debtreduction}{progress} -= ($payloans * $loanamount);
                                      $cash += ($payloans * $loanamount);
                                      $debt -= $payloans;
                                      expendcash(($payloans * $loanamount), "budget", "debt reduction");
                                    }}
                                  if ($debt <= 0) {
                                    $cash += $budget{debtreduction}{progress};
                                    $budget{debtreduction}{progress} = 0;
                                  }
                                },
                              },
            # TODO:
            #  * Lobbyists, who promote friendly legislation to increase prices on eggs and chicken meat.
            #  * Ability to manually purchase bonds.
            #  * Ability to buy and sell stocks.
          );
my @bythedozen = (qw(1 12 144 1728 faireu eaurie passel clutch batallion
                     army myriad klatch)); # jankette disabled for now; we will push the player
                                           # toward phase 2 instead.
my @bytens = (qw(1 10 100 1000 25000 250000 5000000 hundmil billion 25b 250b));
my @licensetype = (qw(countylicense provincelicense nationlicense worldlicense cancel));

%asset   =  ( egg => +{ id     => "egg",
                        name   => "egg",
                        plural => "eggs",
                        desc   => "A fresh chicken egg is part of a balanced breakfast.",
                        value  => 4,
                        sort   => 1,
                        (map { $_ => 1 } qw(product egg)),
                      },
              dozen => +{ id      => "dozen",
                          name    => "dozen eggs",
                          plural  => "dozen eggs",
                          # Dimensions approximately 12" x 4" x 2.75"
                          desc    => "This carton contains one dozen fresh eggs.",
                          value   => 60,
                          sort    => 2,
                          (map { $_ => 1 } qw(product egg)),
                        },
              gross => +{ id     => "gross",
                          name   => "gross of eggs",
                          plural => "gross of eggs",
                          # Dimensions approximately 12" x 16" x 9"
                          desc   => "This case contains twelve dozen fresh eggs.",
                          value  => 850,
                          sort   => 3,
                          (map { $_ => 1 } qw(product egg)),
                        },
              palletload => { id     => "palletload",
                              name   => "pallet of eggs",
                              plural => "pallets of eggs",
                              # Dimensions 48" x 40" x 51", holds 6480 eggs.
                              # Holds 9 cases per layer (16 * 3 == 48; 12 * 3 == 36)
                              # Adds 6" to height, so five layers (5 * 9 == 45) + 6 == 51"
                              # 5 layers at 9 cases per layer == 45 gross, or 6480 eggs.
                              desc   => "This shipping pallet is stacked with 45 cases of fresh eggs.",
                              value  => 45000,
                              sort   => 4,
                              (map { $_ => 1 } qw(product egg)),
                            },
              containerload => { id     => "containerload",
                                 name   => "shipping container of eggs",
                                 plural => "containers of eggs",
                                 # Dimensions: 40' x 8' x 8'6".
                                 # Refrigerated.  Holds 24 pallets of eggs (12 rows of 2).
                                 desc   => "This shipping container holds 24 pallets of fresh eggs.",
                                 value  => 1200000,
                                 sort   => 5,
                                 (map { $_ => 1 } qw(product egg)),
                               },
              panamaxload => { id      => "panamaxload",
                               name    => "freighter loaded with eggs",
                               plural  => "freighters loaded with eggs",
                               # Dimensions: 1200' x 168' x 240' (50' draft, 190' above water).
                               # Holds 13000 TEU, i.e., 6500 of our 40' containers.
                               desc    => "This freighter is loaded with 6500 containers of fresh eggs.",
                               value   => 9000000000,
                               retail  => 10108800000,
                               sort    => 6,
                               (map { $_ => 1 } qw(product egg)),
                             },
              podload => +{ id     => "podload",
                            name   => "cargo pod of eggs",
                            plural => "cargo pods of eggs",
                            desc   => "This cargo pod holds 1024 surface freighters of eggs fresh from Earth, a delicacy sure to arouse interest on any colony.",
                            value  => 12000000000000,
                            sort   => 7,
                          },
              chick => +{ id      => "chick",
                          name    => "baby chick",
                          desc    => "Baby chicks are cute.  They can grow up into hens or, sometimes, roosters.",
                          assetfg => "yellow",
                          value   => 60,
                          sort    => 100,
                          (map { $_ => 1 } qw(product good chicken)),
                          housein  => "nursery",
                          buyqtty  => [@bythedozen],
                          unlocked => +{ buy => +{ 1 => 1, }, },
                          lifespan => +{ months => 7, }, # includes time to hatch;
                          # at EOL, a chick may grow up into a hen (or a rooster); this is handled by expire_asset()
                        },
              hen => +{ id           => "hen",
                        name         => "laying hen",
                        sellname     => "roasting hen",
                        sellplural   => "roasting hens",
                        assetfg      => "yellow",
                        desc         => "A good laying hen produces eggs on a regular basis.",
                        value        => 400,
                        sort         => 101,
                        (map { $_ => 1 } qw(product good chicken)),
                        housein      => "coop",
                        buyqtty      => [@bythedozen],
                        unlocked     => +{ buy => +{ 1 => 1, }, },
                        lifespan     => +{ years => 8 },
                        needvitamins => "1970-01-31",
                      },
              rooster => +{ id         => "rooster",
                            name       => "rooster",
                            sellname   => "rooster for soup",
                            sellplural => "roosters for soup",
                            assetfg    => "red",
                            desc       => "With a rooster around, sometimes your hens will produce chicks.",
                            value      => 1200,
                            sort       => 102,
                            (map { $_ => 1 } qw(product good chicken)),
                            housein    => "coop",
                            buyqtty    => [@bythedozen],
                            unlocked   => +{ buy => +{ 1 => 1, }, },
                            lifespan   => +{ years => 8 },
                          },
              chickenfeed => +{ id       => "chickenfeed",
                                name     => "chicken feed",
                                plural   => "chicken feed",
                                desc     => "Chickens have to eat.",
                                assetfg  => "cyan",
                                value    => 180, # That's per bag, not per serving.
                                sort     => 200,
                                (map { $_ => 1 } qw(supply good)),
                                buyqtty  => [qw(feedbag feedpallet feedtruck feedwarehouse asneeded_feed)],
                                # That's a short list of quantities because after a certain point, you buy feed factories instead.
                                unlocked => +{ buy => +{ feedbag => 1, }, },
                              },
              vitamins => +{ id         => "vitamins",
                             name       => "vitamins",
                             plural     => "vitamins",
                             desc       => "Vitamins improve the health of your chickens.",
                             assetfg    => "cyan",
                             value      => 10, # That's an adult dose, per month; chicks use less.
                             sort       => 250,
                             (map { $_ => 1 } qw(supply good)),
                             buyqtty    => [qw(dose dozendoses 144 1728 faireu eaurie passel clutch
                                               batallion army myriad klatch asneeded)],
                           },
              carton => +{ id      => "carton",
                           name    => "egg carton",
                           desc    => "Customers will pay more for your eggs if they are nicely packaged.  Holds one dozen.",
                           assetfg => "white",
                           buyqtty => [@bythedozen, "asneeded"],
                           value   => 1,
                           sort    => 300,
                           (map { $_ => 1 } qw(good supply packaging)),
                         },
              case => +{ id      => "case",
                         name    => "egg case",
                         assetfg => "white",
                         desc    => "Stores will pay more for your eggs if they are neatly packaged.  Holds 12 cartons.",
                         value   => 5,
                         sort    => 301,
                         buyqtty => [@bythedozen, "asneeded"],
                         (map { $_ => 1 } qw(good supply packaging)),
                       },
              emptybag => +{ id      => "emptybag",
                             phase   => 2,
                             name    => "bag",
                             assetfg => "white",
                             desc    => "Chicken feed is sold in bags.",
                             value   => 1,
                             sort    => 302,
                             buyqtty => [qw(144 1728 faireu eaurie passel clutch batallion army
                                            myriad klatch jankette asneeded)],
                           },
              emptypallet => +{ id      => "emptypallet",
                                name    => "pallet",
                                assetfg => "white",
                                desc    => "Stores will pay more for your product if it is nicely palleted up for delivery.  Holds 45 cases or 25 large bags.",
                                value   => 100,
                                sort    => 305,
                                buyqtty => [@bythedozen, "asneeded"],
                                (map { $_ => 1 } qw(good supply packaging)),
                              },
              emptycontainer => +{ id      => "emptycontainer",
                                   name    => "shipping container (rental)",
                                   desc    => "Distributors charge less to deliver your goods if they are packed in standard intermodal shipping containers.  Holds 24 pallets.",
                                   value   => 20000,
                                   sort    => 306,
                                   assetfg => "grey",
                                   buyqtty => [@bythedozen, "asneeded"],
                                   (map { $_ => 1 } qw(good supply packaging)),
                                 },
              emptyfreighter => +{ id      => "emptyfreighter",
                                   name    => "panamax freighter (rental)",
                                   desc    => "Loading your goods onto a freighter allows you to sell them to international markets, which pay a higher price than the domestic market.  This freighter is designed for the new locks, so it holds 6500 forty-foot shipping containers (1300 TEU).",
                                   sort    => 307,
                                   assetfg => "grey",
                                   value   => 120000000,
                                   buyqtty => [@bythedozen, "asneeded"],
                                   (map { $_ => 1 } qw(good supply packaging)),
                                 },
              emptypod => +{ id      => "emptypod",
                             name    => "cargo pod (rental)",
                             desc    => "Packing your goods in a standard cargo pod lets you sell them all around the solar system.  Holds 1024 surface freighters.",
                             assetfg => "grey",
                             sort    => 308,
                             value   => 200000000000,
                             buyqtty => [@bythedozen, "asneeded"],
                             (map { $_ => 1 } qw(good supply packaging)),
                           },
              coop => +{ id       => "coop",
                         name     => "chicken coop",
                         desc     => "Holds up to 30 chickens.  Takes up 300 square feet on your land.",
                         capacity => 30,
                         value    => 500000,
                         landsize => 300,
                         minqtty  => 1,
                         sort     => 550,
                         assetfg  => "brown",
                         buyqtty  => [@bytens, "asneeded"],
                         (map { $_ => 1 } qw(good housing)),
                       },
              nursery => +{ id        => "nursery",
                            name      => "chick nursery",
                            desc      => "Holds up to 300 chicks.  Takes up 10 square feet on your land.",
                            sort      => 500,
                            capacity  => 300,
                            landsize  => 10,
                            minqtty   => 1,
                            value     => 15000,
                            assetfg   => "brown",
                            buyqtty  => [@bytens, "asneeded"],
                            (map { $_ => 1 } qw(good housing)),
                          },
              acre => +{ id       => "acre",
                         name     => "acre of land",
                         plural   => "acres of land",
                         desc     => "Land, on which you can build things, such as chicken coops.",
                         value    => 5000000,
                         sort     => 700,
                         assetfg  => "green",
                         buyqtty  => [@bytens, "asneeded"],
                         (map { $_ => 1 } qw(good housing)),
                         # An acre is nominally 43560 square feet, but you can't actually use quite 100%
                         # of that in practice, because among other things you can't build right at the
                         # edge, and you need paths between the buildings.  For simplicity, we'll say
                         # that an acre can support forty thousand square feet of buildings.
                         capacity => 40000,
                         minqtty  => 1,
                         licenseneeded => "countylicense",
                       },
              ffactory => +{ unlocked => +{ buy => +{ }},
                             unlcrit  => +{ chick   => 100000000,
                                            hen     => 10000000,
                                            rooster => 1000000,
                                          },
                             id       => "ffactory",
                             name     => "feed factory",
                             desc     => "Produces chicken feed.",
                             (map { $_ => 1 } qw(good)),
                             assetfg  => "azure",
                             value    => 50000000,
                             resale   => 30000000,
                             output   => +{ chickenfeed => 200000, },
                             buyqtty  => [@bytens, "asneeded"],
                             landsize => 200000, # five acres
                             sort     => 800,
                           },
              feedbag => +{ id     => "feedbag",
                            phase  => 2,
                            key    => "b",
                            name   => "bag of chicken feed",
                            plural => "bags of chicken feed",
                            value  => 50, # The consumer pays 180, with markup.
                            (map { $_ => 1 } qw(product feed)),
                          },
              feedpallet => +{ id     => "feedpallet",
                               phase  => 2,
                               name   => "pallet of chicken feed",
                               plural => "pallets of chicken feed",
                               desc   => "This pallet is stacked with 25 large bags of chicken feed.",
                               retail => 3600, # 144 / bag
                               value  => 1400, # 56 / bag
                               (map { $_ => 1 } qw(product feed)),
                             },
              feedcontainer => { id     => "feedcontainer",
                                 phase  => 2,
                                 name   => "shipping container of chicken feed",
                                 plural => "shipping containers of chicken feed",
                                 # Dimensions: 40' x 8' x 8'6".
                                 # Holds 24 pallets of chicken feed (12 rows of 2).
                                 desc   => "This shipping container holds 24 pallets of chicken feed.",
                                 retail => 72000, # 120 / bag
                                 value  => 36000, # 60 / bag
                                 (map { $_ => 1 } qw(product feed)),
                               },
              feedfreighter => +{ id      => "feedfreighter",
                                  phase   => 2,
                                  name    => "freighter loaded with chicken feed",
                                  plural  => "freighters loaded with chicken feed",
                                  desc    => "This freighter is loaded with 6500 containers of chicken feed.",
                                  # At 25 x 24 = 600 bags / container, 6500 containers = 3.9 million bags
                                  retail  => 390000000, # wholesale = 100 per bag
                                  value   => 250000000, # 64.10 per bag
                                  (map { $_ => 1 } qw(product feed)),
                                },
              feedpod => +{ id     => "feedpod",
                            phase  => 2,
                            name   => "cargo pod full of chicken feed",
                            plural => "cargo pods of chicken feed",
                            desc   => "This cargo pod holds 1024 surface freighters of chicken feed.",
                            value  => 300000000000,
                            retail => 475000000000,
                          },
              license => +{ id      => "license",
                            name    => "business license",
                            plural  => "business licenses",
                            desc    => "Businesses must be licensed in each jurisdiction where they do business.",
                            value   => $buyqtty{countylicense}{value},
                            buyqtty => [@licensetype],
                          },
              # TODO:
              #  * Licenses that allow you to operate in more jurisdictions, increasing the # of acres you can own.  County license, state license, national license, global license, system license, sector license, galaxy license, ...
              #  *
            );

our @breedmsg = (undef,
                 qq[Your breeding program has produced healthier chickens.], # This is the default message, for levels that don't provide a specific effect.
                 # TODO: certain breed levels should provide specific effects.
                );
our @genmsg = (undef,
               qq[Your geneticists have produced better chickens.], # Default message for most genlvl values.
               # TODO: certain genetic levels should provide more specific effects.
              );

#for (1 .. 20) {
#  my $c = generate_county();
#  print "$$c{name} ($$c{capitalword}: $$c{capital}),\n\t $$c{size} acres of which $$c{available_land} are available at $$c{landcost}/acre.\n";
#}
#exit 0;
#
#if ($option{debug} or $option{writepricelist}) {
#  writepricelist();
#}

if (-e ($option{savefile} || catfile(get_config_dir(), "eggs.save"))) {
  restoregame();
} else {
  %windowitem = init_windowitems();
  ngp();
}
push @message, ["Press F1 for help.", "help"];
#push @message, ["Cash in excess of " . shownum($investcashover) . " will be automatically invested.", "debug"];
refreshscreen();

#################################################################################################
#################################################################################################
###
###                                     M A I N    L O O P :
###
#################################################################################################
#################################################################################################

while (1) {
  iterate() unless $paused; # Do the egg-game-specific once-per-turn things.

  for my $w (@widget) {
    if (not $$w{__INTERVAL_POS__}) {
      dowidget($w, $screen);
      $$w{__INTERVAL_POS__} = $$w{interval};
    } else {
      redraw_widget($w, $screen);
    }
    $$w{__INTERVAL_POS__} = $$w{__INTERVAL_POS__} - 1 if $$w{interval};
  }
  updatetopbar($wtopbar);
  draweggscreen($screen);

  my $delay = $option{delay} || 1;
  while ($delay > 0) {
    my $since = [gettimeofday()];
    my $key = ReadKey($delay);
    process_key($key) if defined $key;
    my $ival = tv_interval($since);
    $delay -= $ival;
  }
}
exit 0; # Can't Happen
# Subroutines follow...


#################################################################################################
#################################################################################################
###
###                                E G G    G A M E    L O G I C :
###
#################################################################################################
#################################################################################################

sub ngp {
  generate_world() if not @world;
  generate_nation() if not @nation;
  generate_province() if not @province;
  generate_county() if not @county;
  my $relative = $relative[0]; @relative = randomorder(@relative);
  #use Data::Dumper; print Dumper(+{ "relatives" => \@relative, chosen_relative => $relative, });
  my ($noun, $pronoun, $possessive) = @$relative;
  my $feed = int(($asset{chickenfeed}{qtty} || 4) / 4); $feed = 4320 if $feed < 4320;
  my $nurs = int(($asset{nursery}{qtty} || 1) / (int($asset{coop}{qtty} * 2 / 3) || 1)); $nurs = 1 if $nurs < 1;
  my $acre = int(log(($asset{acre}{qtty} || 1)) / log(tau * 2 / 3)) + int($asset{acre}{qtty} / 27);
  my $vita = int($asset{vitamins}{qtty} / 4);
  my $coop = int(log(($asset{coop}{qtty} || 1)) / log(tau)) + int($asset{coop}{qtty} / 25) + 1; $coop = $nurs * 5 if $coop > $nurs * 5;
  my $fact = int(log(($asset{ffactory}{qtty} || 1)) / log(tau)) || 0;
  if ($fact > 10) {
    debuglog("Factory Phase, Activate.");
    $gamephase = 2 if $gamephase < 2;
  }
  while (((($coop * 2 * $asset{coop}{landsize})
           + ($nurs * 2 * $asset{nursery}{landsize})
           + ($fact * 1 * $asset{ffactory}{landsize}))
          > ($acre * $asset{acre}{capacity}))
         and ($acre < $asset{acre}{qtty})) {
    # TODO: use a more efficient algorithm here.  This is O(n).
    $acre++;
  }
  $acre ||= 1;
  # Most of your late benefactor's land goes back on the market:
  for my $c (@county) {
    $$c{available_land} += $$c{owned_land};
    $$c{owned_land} = 0;
  }
  # You don't inherit most of the business licenses:
  for my $j (@county, @province, @nation, @world) {
    $$j{licensed} = 0;
  }
  # Start the player with licenses to operate in one county with a pretty standard land cost:
  $county[0]{licensed} = $province[0]{licensed} = $nation[0]{licensed} = $world[0]{licensed} = 1;
  $county[0]{landcost} = $asset{acre}{value};
  # For gameplay reasons, we must ensure that there is enough land in the remaining licensed county
  # for the player to get "off the ground".  (Gameplay is more important than realism.)  The excuse,
  # from a story perspective, can be that some of the land that was not left to you in the will,
  # becomes available for purchase due to being on the market:
  $county[0]{available_land} += $county[0]{owned_land} - $acre;
  $county[0]{owned_land} = $acre;
  if ($county[0]{avaliable_land} <= $acre) {
    # Need some room to grow.  So, this county, umm, just merged with an adjacent one, or something:
    $county[0]{avaliable_land} += $acre;
    $county[0]{size} = $county[0]{owned_land} + $county[0]{avaliable_land}
      + 1; # enough room for the county courthouse and sherrif's office.
  }
  my ($c) = $county[0];
  @message  = (["So there you are, penniless and fresh out of school, wondering what you're going to do now, and it seems your $noun has just died; and $pronoun left you "
                . (($acre == 1) ? "an acre" : shownum($acre) . " acres") . " of land near $$c{capital}, the $$c{capitalword} of $$c{name}, with "
                . ((($fact >= 1) ? (($fact == 1)
                                    ? "a chicken-feed factory "
                                    : shownum($fact) . " chicken-feed factories, ")
                    : ""))
                . ((($coop == 1) ? "a chicken coop" : (shownum($coop)) . " chicken coops"))
                . " on it, and $possessive best laying hen.", "story"]);
  @messageline = ();
  rewrap_message_log($wmessages);
  %cashflow = map { $_ => +{} } qw(current lastmonth year lastyear total);
  $cash = $debt = $creditrating = $maxcreditrating = 0; @bond = ();
  for my $bk (keys %budget) {
    $budget{$bk}{progress} = undef;
  }
  $runstarted = $date;
  $birthdate  = $runstarted->clone()->subtract( years  => (19 + int rand 6),
                                                days   => (1 + int rand 365), );
  $ngpeta     = $birthdate->clone()->add(years => (45 + int rand rand 55),
                                         days  => (1 + int rand 365));
  $creditrating = 0;
  for my $symbol (keys %stock) {
    $stock{$symbol}{owned} = 0;
  }

  my %keepasneeded = map { $_ => 1 } qw(chickenfeed
                                        carton case emptypallet emptycontainer emptyfreighter emptypod
                                        acre); # TODO: licenses?
  # I had to take vitamins off the keep-as-needed list because
  # sometimes they ran out when there happened to be enough cash on
  # hand to buy an unnecessarily large quantity of them, but that
  # money was needed for food.  This resulted in starving chickens.
  for my $k (keys %asset) {
    $asset{$k}{qtty} = 0;
    $asset{$k}{agegroup} = +[];
    $asset{$k}{asneeded} = undef unless $keepasneeded{$k};
    # Unlocked things stay unlocked.
  }
  addasset("hen", 1);
  addasset("chickenfeed", $feed);
  addasset("carton", 144) if $asset{carton}{unlocked}{buy}{144};
  addasset("coop", $coop);
  addasset("nursery", $nurs);
  addasset("acre", $acre);
  addasset("ffactory", $fact);
  if ($option{pauseonngp}) {
    toggle_pause("force_pause_on");
  }
}

sub iterate {
  my ($ival) = @_;
  $ival ||= "days"; # I was originally thinking to allow the user to unlock the ability to set this to
                    # weeks, months, maybe even years; but eventually I thought better of it.  If the
                    # user needs to let huge amounts of time pass quickly, it's a sign that the pace of
                    # progress or development has slowed too much, and that should be addressed instead.
  my $dt = $date->clone();
  $date = $date->add($ival => 1);
  #$$wgameclock{faketime} = $date;
  my $days = 0;
  while ($dt->ymd() lt $date->ymd()) {
    $dt = $dt->add(days => 1);
    $days++;
  }
  debuglog("iterate(): $days days pass.");
  if ($ngpeta->ymd() lt $date->ymd()) {
    if ($asset{hen}{qtty} < 1) {
      gameover("Your will calls for your best prize laying hen to be left to your heir.\nUnfortunately, you no longer have that hen.\nYour will is tied up in probate for decades, and your heir never gets into the egg business.");
    }
    push @message, ["Your will calls for your best prize laying hen to be left to your heir...", "story"];
    ngp();
  } elsif ((ref $birthdate) and # for backward compatibility with old game files
           ($birthdate->month() eq $date->month()) and
           ($birthdate->mday() eq $date->mday())) {
    my $age = int($date->year() - $birthdate->year());
    push @message, [qq[Happy Birthday!  You are now $age years old.], "occasion"];
  }
  for my $sym (keys %stock) {
    # TODO: update the indicators, model the economy, etc.
    my $mvt = (($$wticker{rotate_counter} % 3) ? $stock{$sym}{movement} : (((int rand 100) - 45) / 10));
    $stock{$sym}{price} += $mvt;
    $stock{$sym}{movement} = $mvt;
    if ($stock{$sym}{price} < 50) {
      push @message, [$stock{$sym}{name} . " ($sym) delisted.", "stock"];
      $stock{$sym} = undef;
    } elsif (($stock{$sym}{price} > 50000000) and ($mvt > 5) and (20 > rand 100)) {
      my $multiplier = int($stock{$sym}{price} / 50000000);
      $stock{$sym}{shares} *= $multiplier;
      $stock{$sym}{owned}  *= $multiplier;
      $stock{$sym}{price}   = $stock{$sym}{price} / $multiplier;
      push @message, [$stock{$sym}{name} . " ($sym) splits, " . $multiplier . "-for-1.", "stock"];
    }
  }
  for my $producer (grep { ($asset{$_}{qtty} > 0) and (ref $asset{$_}{output}) } keys %asset) {
    # Assets that produce other assets, for now, is just feed factories making chicken feed.
    # But I implemented it in a general way, because the nature of idle games is, they grow.
    debuglog("iterate: $asset{$producer}{qtty} "
             . sgorpl($asset{$producer}{qtty}, ($asset{$producer}{name} || $producer), $asset{$producer}{plural}));
    for my $product (keys %{$asset{$producer}{output}}) {
      $asset{$product}{qtty} += $asset{$producer}{output}{$product} * $asset{$producer}{qtty};
      #push @message, ["Your " . shownum($asset{$producer}{qtty}) . " "
      #                . sgorpl($asset{$producer}{qtty}, ($asset{$producer}{name} || $producer), $asset{$producer}{plural})
      #                . " " . inflectverb($asset{$producer}{qtty}, "produces", "produce")
      #                . " " . shownum($asset{$producer}{output}{$product}  * $asset{$producer}{qtty}) . " "
      #                . sgorpl($asset{$producer}{output}{$product} * $asset{$producer}{qtty}, ($asset{$product}{name} || $product), $asset{$product}{plural})
      #                . ".", "assetgain"];
    }}
  for my $lockedproducer (grep { (ref $asset{$_}{output}) and
                                   not $asset{$_}{unlocked}{buy}{$asset{$_}{buyqtty}[0]}
                                 } keys %asset) {
    debuglog("iterate: Can we unlock '$lockedproducer'?");
    for my $prereq (keys %{$asset{$lockedproducer}{unlcrit}}) {
      if ($asset{$prereq}{qtty} >= $asset{$lockedproducer}{unlcrit}{$prereq}) {
        my ($qtty) = @{$asset{$lockedproducer}{buyqtty}};# $qtty ||= 1;
        debuglog("Attempting to unlock buy quantity $qtty ($buyqtty{$qtty}{id})");
        $asset{$lockedproducer}{unlocked}{buy}{$buyqtty{$qtty}{id}} ||= 1;
        debuglog("Yes, unlocked " . $asset{$lockedproducer}{plural} || makeplural($asset{$lockedproducer}{name} || $lockedproducer));
      }}}
  if (($asset{vitamins}{qtty} > 0) or ($asset{vitamins}{asneeded})) {
    for my $chickentype (grep { $asset{$_}{qtty} > 0 } qw(hen rooster chick)) {
      $asset{$chickentype}{needvitamins} ||= $date->ymd();
      if ($asset{$chickentype}{needvitamins} le $date->ymd()) {
        my $dosesneeded = ($chickentype eq "chick")
          ? int(($asset{$chickentype}{qtty} + 9) / 10)
          : $asset{$chickentype}{qtty};
        if (($asset{vitamins}{qtty} < $dosesneeded) and
            ($asset{vitamins}{asneeded})) {
          buyatleast("vitamins", $dosesneeded - $asset{vitamins}{qtty}, "need");
        }
        if ($asset{vitamins}{qtty} >= $dosesneeded) {
          my $nextmonth = $date->clone()->add(days => 30);
          $asset{vitamins}{qtty} -= $dosesneeded;
          $asset{$chickentype}{needvitamins} = $nextmonth->ymd();
        }}}} else {
          $asset{vitamins}{unlocked}{buy}{dose} ||= 1;
        }
  if ($date->mday() == 1) {
    update_levels();
    monthly_expenses();
    adjust_primerate();
    savegame() if $option{autosave} eq "monthly";
    if ($option{debug}) {
      use Data::Dumper;
      debuglog("Cashflow: " . Dumper(\%cashflow, +{ year  => $date->year(),
                                                    month => $date->month(),
                                                    mday  => $date->mday()}));
    }
    $cashflow{lastmonth} = $cashflow{current};
    $cashflow{current} = +{};
    $cashflow{sc}{lastmonth} = $cashflow{sc}{current};
    $cashflow{sc}{current} = +{};
    if ($date->month() == 1) {
      $cashflow{lastyear} = $cashflow{year};
      $cashflow{year} = +{};
      $cashflow{sc}{lastyear} = $cashflow{sc}{year};
      $cashflow{sc}{year} = +{};
      savegame() if $option{autosave} eq "annually";
    }
  }
  if (10 > int rand 4000) {
    # We add new stocks from time to time starting from the very beginning, so that by the time the
    # player unlocks the stock-market feature, there will be a pool of existing stocks.  We don't
    # need to expend computational cycles on stock _activity_ until that happens, but there need to
    # be some stocks created.
    my $ns = newstock();
    $stock{$$ns{symbol}} = $ns;
    # The following message is temporary, for debugging purposes.
    push @message, ["$$ns{name} goes public, ticker symbol $$ns{symbol}, "
                    . shownum($$ns{shares}) . " shares at " . shownum($$ns{price})
                    . ", indicators: " . shownum($$ns{sales}) . ", " . shownum($$ns{assets})
                    . ", +" . shownum($$ns{cash}) . ", -" . shownum($$ns{debt}) . ".", "stock"]
      if $gamephase >= 2;
  }
  my $mealsneeded = $days * int($asset{hen}{qtty} + $asset{rooster}{qtty} + (($asset{chick}{qtty} + 3) / 7));
  $asset{chickenfeed}{qtty} -= $mealsneeded;
  debuglog("chickenfeed: $asset{chickenfeed}{qtty}");
  my $excess = 0;
  if (($asset{chickenfeed}{qtty} <= 0) and ($asset{chickenfeed}{asneeded})) {
    buyatleast("chickenfeed", $mealsneeded, "need");
  } elsif ($gamephase >= 2) {
    $excess = $asset{chickenfeed}{qtty} - ($mealsneeded * 31 * $asset{chick}{lifespan}{months});
  }
  if ($asset{chickenfeed}{qtty} + ($mealsneeded / 2) < 0) {
    for my $x (["hen"     => int(valuefromexpectations(12, $asset{hen}{qtty}))],
               ["rooster" => int(valuefromexpectations(15, $asset{rooster}{qtty}))],
               ["chick"   => int(valuefromexpectations(30, $asset{chick}{qtty}))],
              ) {
      my ($atype, $numdead) = @$x;
      debuglog("Starvation cycle: $atype, $numdead");
      my $degrouped = degroup_chickens($atype, $numdead);
      #Factored this out to degroup_chickens():
      #for my $group (@{$asset{$atype}{agegroup} || +[]}) {
      #  my $kill = $numdead - ($degrouped || 0);
      #  $kill = $$group{qtty} if $kill > $$group{qtty};
      #  $$group{qtty} -= $kill;
      #  $asset{$atype}{qtty} -= $kill;
      #  $degrouped += $kill;
      #}
      if ($degrouped > 0) {
        push @message, [$degrouped . " " . sgorpl($degrouped, $asset{$atype}{name}) . " starved.", "assetloss"];
        # We aren't going to _mention_ it to the player, but the others will eat them
        # (which helps prevent mass-starvation events from becoming a tpk too quickly):
        $asset{chickenfeed}{qtty} += (($atype eq "chick") ? 1 : 6) * $degrouped;
      }
    }
  }
  $asset{chickenfeed}{qtty} = 0 if $asset{chickenfeed}{qtty} < 0;
  my $laid = int(valuefromexpectations(chicken_health_ev(60, "hen", "laying"),
                                       $asset{hen}{qtty}));
  if ($asset{rooster}{qtty} > 0) {
    # Convert some of the eggs into chicks:
    my $mayconvert = int ($laid / 10);
    if ($mayconvert == 0) {
      $mayconvert = 1 if (($laid * 10) > rand 100);
    }
    if ($mayconvert > 0) {
      my $max = 10 * $asset{rooster}{qtty} + rand(10 * $asset{rooster}{qtty});
      $max = $mayconvert if $max > $mayconvert;
      $max = 1 if (($max < 1) and ($asset{rooster}{qtty} > 0));
      my $chicks = valuefromexpectations(chicken_health_ev(25, "rooster", "fertilization"), $max);
      if ($chicks > 0) {
        $laid -= $chicks;
        # This message gets way too spammy.  Maybe aggregate it per month?
        #push @message, [shownum($chicks) . " " . sgorpl($chicks, "baby chick")
        #                . " " . isare($chicks). " born.",
        #                "assetgain"];
        my $keepchicks = $chicks;
        my $soldchicks = 0;
        while ($keepchicks and not canhouse($keepchicks, "nursery")) {
          # Sell off excess chicks if there isn't enough nursery space.
          my $sell = ($keepchicks < 10) ? 1 : int($keepchicks / 2);
          my $per  = ($option{sellchickens} eq "m") ? 1 : ($asset{chick}{value} / 2);
          my $price = int($sell * $per);
          gaincash($price, "sales", "chicks");
          $keepchicks -= $sell;
          $soldchicks += $sell;
          # If selling live chicks, your competitors get any genetic enhancements you've got.
          if (($sell > 0) and ($option{sellchickens} ne "m")) {
            $genleak = $genlvl if $genleak < $genlvl;
          }
        }
        $asset{nursery}{unlocked}{buy}{1} ||= 1 if $soldchicks;
        push @message, ["Sold " . shownum($soldchicks) . " " .
                        sgorpl($soldchicks, (($option{sellchickens} eq "m") ? "chick nugget" : "chick"))
                        . ".", "assetsold"]
          if $soldchicks;
        addasset("chick", $keepchicks) if $keepchicks;
      }
    }
  }
  $asset{egg}{qtty} += $laid;
  my @egggrouping = ([ 12,   "egg", "dozen", "carton"],
                     [ 12,   "dozen", "gross", "case"],
                     [ 45,   "gross", "palletload", "emptypallet", ],
                     [ 24,   "palletload", "containerload", "emptycontainer" ],
                     [ 6500, "containerload", "panamaxload", "emptyfreighter" ],
                     [ 1024, "panamaxload", "podload", "emptypod", ],
                    );
  my @feedgrouping = ([ 150,  "chickenfeed", "feedbag", "emptybag"],
                      [ 25,   "feedbag", "feedpallet", "emptypallet"],
                      [ 24,   "feedpallet", "feedcontainer", "emptycontainer" ],
                      [ 6500, "feedcontainer", "feedfreighter", "emptyfreighter" ],
                      [ 1024, "feedfreighter", "feedpod", "emptypod" ],
                     );
  my @grp = @egggrouping;
  if (($gamephase >= 2) and ($excess > $asset{feedbag}{number})) {
    @grp = (@grp, @feedgrouping);
  }
  for my $grouping (@grp) {
    my ($per, $item, $group, $container) = @$grouping;
    my $sellqtty = ($item eq "chickenfeed") ? $excess : $asset{$item}{qtty};
    my $n = int($sellqtty / $per);
    if ($asset{$container}{qtty} < $n) {
      if ($asset{$container}{asneeded}) {
        my $containersneeded = $n - $asset{$container}{qtty};
        buyatleast($container, $containersneeded, "need");
      } else {
        $asset{$container}{unlocked}{buy}{1} ||= 1;
      }
      $n = $asset{$container}{qtty} if $n > $asset{$container}{qtty};
    }
    if ($asset{$container}{qtty} >= $n) {
      $asset{$container}{qtty} -= $n;
      $asset{$item}{qtty}      -= $n * $per;
      $asset{$group}{qtty}     += $n;
      debuglog("Grouped " . $n * $per . " of $item into $n of $container.")
        if $option{debug} > 5;
    } else {
      debuglog("Failed to group " . $n * $per . " of $item into $n of $container.");
    }
  }
  my $sellunit = "egg";
  for my $u (qw(dozen gross paletteload containerload panamaxload podload)) {
    if ($asset{$u}{qtty} > 0) {
      $sellunit = $u;
    }}
  my $newmoney = $asset{$sellunit}{value} * $asset{$sellunit}{qtty};
  $asset{$sellunit}{qtty} = 0;
  gaincash($newmoney, "sales", "eggs");
  $sellunit = "feedbag";
  for my $u (qw(feedpallet feedcontainer feedfreighter feedpod)) {
    if ($asset{$u}{qtty} > 0) {
      $sellunit = $u;
    }}
  $newmoney = $asset{$sellunit}{value} * $asset{sellunit}{qtty};
  $asset{$sellunit}{qtty} = 0;
  gaincash($newmoney, "sales", "chicken feed") if $newmoney;
  # Things age over time:
  for my $atype (grep { $asset{$_}{lifespan} } keys %asset) {
    for my $grp (@{$asset{$atype}{agegroup}}) {
      if ($$grp{expire} le $date->ymd()) {
        expire_asset($atype, $$grp{qtty});
        $$grp{qtty} = 0;
      }}
    $asset{$atype}{agegroup} = [grep { $$_{qtty} } @{$asset{$atype}{agegroup}}];
  }
}

sub gameover {
  my ($msg) = @_;
  print $reset . gotoxy(0,0)
    . chr(27) . "[2J" # clear-screen
    . gotoxy(0,0)
    . $reset . $msg . "\n\n";
  unlink $option{savefile} unless $option{debug};
  exit 0;
}

sub namecreditrating {
  my ($n) = @_;
  if ($n < -8) {
    return "execrable";
  } elsif ($n < -4) {
    return "terrible";
  } elsif ($n < -2) {
    return "very bad";
  } elsif ($n < -1) {
    return "bad";
  } elsif ($n < 1) {
    return "poor";
  } elsif ($n < 2) {
    return "mediocre";
  } elsif ($n < 4) {
    return "good";
  } elsif ($n < 8) {
    return "great";
  } elsif ($n < 16) {
    return "fantastic";
  } elsif ($n < 32) {
    return "stupendous";
  } elsif ($n < 64) {
    return "incredible";
  } else {
    return "jaw-dropping";
  }
}

sub update_credit_rating {
  # What follows is not how real-world credit ratings work.  In
  # particular, being in debt (up to a point) _increases_ your credit
  # rating IRL.  But gameplay is more important than realism.
  my $rating = 0;
  my $max = 0; # Max is used mainly to decide whether the player has
               # done enough stuff in the current run to warrant even
               # mentioning the credit rating.  So it doesn't care
               # about good vs bad, only about activity.
  if ($cash > 1000000000000) {
    $rating += clog($cash / 1000000000000);
    $max    += clog($cash / 1000000000000);
  } elsif ($cash < -1000000000000) {
    $rating -= clog(abs($cash / 1000000000000));
    $max    += clog($cash / 1000000000000);
  }
  if ($debt > 0) {
    $rating -= clog($debt); # debt is tracked in trillions.
    $max    += clog($debt);
  }
  if ($cashflow{current}{sales} > 1000000000000) {
    $rating += clog($cashflow{current}{sales} / 1000000000000);
    $max    += clog($cashflow{current}{sales} / 1000000000000);
  }
  # TODO: consider investments

  $maxcreditrating = $max if $max > $maxcreditrating;
  my $changeword = ($rating > ($creditrating + 0.25)) ? "is improving.  Currently it is" :
    (($rating + 0.25 < $creditrating)) ? "is decreasing.  Currently it is" : "is";
  $creditrating = int($rating + ($creditrating * 3) / 4);
  # These messages are a bit spammy.  Limit it to once per quarter.
  if ($maxcreditrating > 2) {
    push @message, ["Your credit rating $changeword " . namecreditrating($creditrating) . ".", "credit"]
      if not ($date->month() % 3);
  }
}

sub update_levels {
  # Breeding program: any results yet?
  my $blvl = int(log(1 + int($cashflow{sc}{total}{budget}{$budget{breeding}{name}} / 1000)));
  if ($blvl > $breedlvl) {
    push @message, [$breedmsg[$blvl] || $breedmsg[1], "budgetaction"];
    $breedlvl = $blvl;
  }
  # Genetic Engineering:
  my $glvl = int(log(1 + int($cashflow{sc}{total}{budget}{$budget{genetics}{name}} / 100000)));
  if ($glvl > $genlvl) {
    push @message, [$genmsg[$glvl] || $genmsg[1], "budgetaction"];
    $genlvl = $glvl;
  }
  # Financial Status:
  update_credit_rating();
}

sub monthly_expenses {
  my ($examsetting) = grep { $$_{name} eq $budget{medexam}{value} } @{$budget{medexam}{enum}};
  if (($$examsetting{timesperyear} > 0) and not ($date->month() % int(12 / $$examsetting{timesperyear}))) {
    my $numofchickens = $asset{hen}{qtty} + $asset{rooster}{qtty} + $asset{chick}{qtty};
    my $numofexams = $asset{hen}{qtty} + $asset{rooster}{qtty} + ($asset{chick}{qtty} / 15);
    if ($numofchickens > 0) {
      my $examscost   = int(30 * $numofexams);
      if (canafford($examscost)) {
        expendcash($examscost, "budget", "medical exams");
        for my $ctype (qw(hen rooster chick)) {
          $asset{$ctype}{examined} = $date->ymd();
        }
        push @message, [(($numofchickens == 1) ? "Your chicken" :
                         ($numofchickens == 2) ? "Both of your chickens" : "All of your chickens")
                        . " receive medical " . sgorpl($numofchickens, "examination") . ".", "budgetaction"];
      } else {
        push @message, ["You cannot afford the scheduled medical "
                        . sgorpl($numofchickens, "examination") . ".", "budgetaction"];
      }
    }}
  if ($debt > 0) {
    my $irate = $primerate + 1;
    if ($creditrating < 0) {
      $irate = ($irate * 1.5) + 0.5;
    } elsif ($creditrating >= 2) {
      $irate -= (log($creditrating) / log(2)) * 0.15;
    }
    $irate = $primerate if $irate < $primerate;
    # So $irate is the Annual Percentage Rate, but we're doing this
    # monthly, and $debt is in trillions of zorkmids.  So for each
    # trillion zorkmids of debt, the amount of interest in a month
    # would be 1/12th of a trillion times the APR divided by 100.
    my $interest = int(($loanamount / 100) * $irate / 12);
    expendcash($interest, "investment", "interest");
  }
}

sub expire_asset {
  my ($atype, $qtty) = @_;
  my $ustahav = $asset{$atype}{qtty};
  $asset{$atype}{qtty} -= $qtty;
  if ($asset{$atype}{qtty} < 0) { $asset{$atype}{qtty} = 0; }
  my %sold;
  if ($atype eq "chick") {
    my $grewup = valuefromexpectations(chicken_health_ev(90, "chick", "hen"), $qtty);
    $grewup = $qtty if $grewup > $qtty;
    my $roosters = ($grewup > 0) ? valuefromexpectations(chicken_health_ev(5, "chick", "rooster"), $qtty) : 0;
    $roosters = int($qtty / 4) if $roosters > ($qtty / 4);
    my $hens = $grewup - $roosters;
    my $remaining = $qtty - $grewup;
    if ($hens > 0) {
      my $keephens = $hens;
      while ($keephens and not canhouse($keephens, "coop")) {
        # Sell off excess hens.  You don't get full value.  If selling
        # off at best price or to a good home, your competitors
        # benefit from genetic enhancements you've created.
        my $sell = ($keephens < 10) ? 1 : int($keephens / 2);
        my $per  = ($option{sellchickens} eq "m")
          ? ($asset{hen}{value} / 3)
          : ($asset{hen}{value} / 2);
        my $price = int($sell * $per);
        gaincash($price, "sales", "hens");
        $keephens -= $sell;
        $sold{hen} += $sell if $sell > 0;
      }
      addasset("hen", $keephens) if $keephens > 0;
      push @message, [shownum($hens) . " " . sgorpl($hens, "chick")
                      . " grew up into " . sgorpl($hens, "a hen", "hens") . ".", "assetgain"];
    }
    if ($roosters > 0) {
      push @message, [shownum($roosters) . " " . sgorpl($roosters, "chick")
                      . " grew up into " . sgorpl($roosters, "a rooster", "roosters") . ".", "assetgain"];
      my $keeproosters = $roosters;
      while ($keeproosters and not canhouse($keeproosters, "coop")) {
        # Sell off excess roosters.  You don't get full value.
        my $sell = ($keeproosters < 10) ? $keeproosters : int($keeproosters / 2);
        my $per  = ($option{sellchickens} eq "m")
          ? ($asset{hen}{value} / 4) # For meat, roosters are actually worth _less_ than hens.  Tougher meat, only good for soup.
          : ($asset{rooster}{value} / 2);
        my $price = int($sell * $per);
        gaincash($price, "sales", "roosters");
        $keeproosters -= $sell;
        $sold{rooster} += $sell if $sell > 0;
      }
      addasset("rooster", $keeproosters) if $keeproosters > 0;
    }
    if ($remaining > 0) {
      my $died = $remaining - $roosters;
      if (($asset{$atype}{qtty} == 0) and ($hens == 0) and ($roosters == 0)) {
        push @message, ["Your " . sgorpl($qtty, "chick") . " died :-(", "assetloss"];
      } else {
        push @message, [shownum($died) . " " . sgorpl($died, "chick") . " died.", "assetloss"];
      }
    }
  } elsif (($atype eq "hen") or ($atype eq "rooster")) {
    if (($atype eq "hen") and ($asset{hen}{qtty} == 0)) {
      addasset("hen", 1); # Don't let the player's last laying hen die of old age.
    }
    my $died = $ustahav - $asset{$atype}{qtty};
    push @message, [shownum($died) . " " . sgorpl($died, $asset{$atype}{name},
                                         $asset{$atype}{plural}) . " died.", "assetloss"]
      if $died > 0;
  } else {
    push @message, ["Error: unanticipated asset expiration: '$atype'.", "bug"];
  }
  if (keys %sold) {
    debuglog("coop unlock " . $asset{coop}{unlocked}{buy}{1}++);
    if ($option{sellchickens} ne "m") {
      $genleak++ if (($genleak < $genlvl) and ( 5 > rand 100));
    }
    push @message, ["Sold " . (commalist(map {
      my $atype = $_;
      my $sname = ($option{sellchickens} eq "m")
        ? ($asset{$atype}{sellname} || $asset{$atype}{name})
        : $asset{$atype}{name};
      my $splur = ($option{sellchickens} eq "m")
        ? ($asset{$atype}{sellplural} || $asset{$atype}{plural})
        : $asset{$atype}{plural};
      shownum($sold{$atype}) . " " . sgorpl($sold{$atype}, $sname, $splur);
    } sort {
      $asset{$a}{value} <=> $asset{$b}{value}
    } keys %sold) . "."), "assetsold"];
  }
}

sub chicken_health_ev {
  my ($baseev, $ctype, $reason) = @_;
  my $ev = $baseev;
  my %multiplier = chicken_health_modifiers($ctype, $reason);
  for my $mk (keys %multiplier) {
    $ev = int($ev * $multiplier{$mk});
  }
  return $ev;
}

sub parseisodate {
  my ($d) = @_;
  my ($y, $m, $day) = $d =~ /(\d{4})-(\d+)-(\d+)/;
  croak "parsedate(): failed to parse, '$d'" if not $day;
  my $tz = $option{localtimezone} || "UTC";
  my $dt;
  eval {
    $dt = DateTime->new( year      => $y,
                         month     => $m,
                         day       => $day,
                         time_zone => $tz,
                       );
  };
  croak "DateTime failure: $d" if not ref $dt;
  return $dt;
}

sub chicken_health_modifiers {
  my ($ctype, $reason) = @_;
  my ($lastexamdate) = $asset{$ctype}{examined} || "1970-01-01";
  my $dt;
  my $sincelastexam; eval {
    my $current = $date->clone();
    $dt = parseisodate($lastexamdate);
    $sincelastexam = $current->subtract_datetime($dt);
  };
  croak "chicken_health_modifiers: problems with last exam date '$lastexamdate' => " . $dt->ymd()
    . "\n" . $@ if not ref $sincelastexam;
  my $monthssincelastexam = ($sincelastexam->years() * 12) + $sincelastexam->months()
    + ($sincelastexam->days() ? 1 : 0);
  ## my $dt = $date->clone();
  ## # TODO: This is O(n).  Replace it with an O(1) formula.
  ## while ($dt->ymd() ge $lastexamdate) {
  ##   $dt = $dt->subtract( months => 1 );
  ##   $monthssincelastexam++;
  ## }
  my %mod = ( vitamins => (($asset{$ctype}{needvitamins} ge $date->ymd())
                           ? 1.1
                           : 1),
              medexams => (1 + (1 / ($monthssincelastexam || 1))),
              # TODO: immunizations
              breeding => (1 + ($breedlvl / 50)),
            );
  my %genrelevant = map { $_ => 1 } qw(laying fertilization);
  if ($genrelevant{$reason}) {
    $mod{genetics} = (1 + ($genlvl / 50));
  }
  return %mod;
}

sub licensedfor {
  my ($neededfor, $number) = @_;
  #warn qq[licensedfor($neededfor, $number)\n];
  my (@c) = grep { $$_{available_land} and $$_{licensed} } @county;
  #warn qq[There are ] . @c . " licensed counties with available land.";
  my $total = 0;
  my $cost  = 0;
  my @usefrom;
  for my $county (@c) {
    $total += $$county{available_land};
    #warn qq[ * $$county{name}, $$county{available_land} acres, running total = $total\n];
    push @usefrom, $county;
    if ($total >= $number) {
      #warn qq[ That's enough.  Purchasing acreage...\n];
      $total = 0;
      for my $uf (@usefrom) {
        my $use = $number - $total;
        $use = $$uf{available_land} if $$uf{available_land} < $use;
        $$uf{available_land} -= $use;
        $$uf{owned_land}     += $use;
        $total += $use;
        $cost  += $use * $$uf{landcost};
        #warn qq[ * $use acres from $$uf{name} for ] . ($use * $$uf{landcost}) . qq[\n];
        expendcash($cost, "investment", "land");
      }
      #warn qq[ Total cost: $cost\n];
      return $total;
    }
  }
  # TODO: add an option to turn auto-license-buying off.
  return buylicensesfor($neededfor, $number - $total);
}

sub buylicensesfor {
  my ($neededfor, $numacres) = @_;
  my (@cl);
  while ($numacres) {
    my %lc;
    my ($c) = generate_county();
    my @jurisdiction;
    my $lcost = 0;
    if (not $$c{licensed}) {
      $lcost += $lc{county} = $buyqtty{countylicense}{value};
      push @jurisdiction, $$c{name};
    }
    my ($p) = grep { $$_{name} eq $$c{parent} } @province;
    if (not $$p{licensed}) {
      $lcost += $lc{provincial} = $buyqtty{provincelicense}{value};
      push @jurisdiction, $$p{name};
    }
    my ($n) = grep { $$_{name} eq $$p{parent} } @nation;
    if (not $$n{licensed}) {
      $lcost += $lc{national} = $buyqtty{nationlicense}{value};
      push @jurisdiction, $$n{name};
    }
    my ($w) = grep { $$_{name} eq $$n{parent} } @world;
    if (not $$w{licensed}) {
      $lcost += $lc{global} = $buyqtty{worldlicense}{value};
    }
    if (canafford($lcost)) {
      for my $j (qw(county provincial national global)) {
        expendcash($lcost, "investment", "licenses") if $lc{$j};
      }
      $$c{licensed} = $$p{licensed} = $$n{licensed} = $$w{licensed} = 1;
      $numacres -= $$c{available_land};
      push @cl, $$c{name};
      return @cl if $numacres <= 0;
    } else {
      push @message, [qq[You can't afford the business licenses for ] . commalist(@jurisdiction) . ".",
                      "actioncancel"];
      return;
    }
  }
}

sub safetobuy {
  my ($atype, $number) = @_;
  debuglog("safetobuy($atype, $number);");
  if ($asset{$atype}{chicken}) {
    #$asset{$asset{$atype}{housein}}{unlocked}{buy}{1} ||= 1
    #  if $asset{$atype}{qtty} >= ($asset{$asset{$atype}{housein}}{capacity} * 4 / 5);
    debuglog(" stb: returning canhouse($number, $asset{$atype}{housein})");
    return canhouse($number, $asset{$atype}{housein});
  } elsif ($asset{$atype}{landsize}) {
    debuglog(" stb: returning canbuild($number, $atype)");
    return canbuild($number, $atype);
  } elsif ($asset{$atype}{licenseneeded}) {
    return licensedfor($atype, $number);
  }
  debuglog(" stb: returning $number");
  return $number;
}

sub canhouse {
  my ($n, $housingtype) = @_;
  # Can we house $n _additional_ chickens in our coops (or chicks in our nurseries)?
  debuglog("canhouse($n, $housingtype)");
  if (not $n) {
    if ($option{debug}) { croak "canhouse(0, $housingtype)"; }
    return; # No infinite loops pls, kthx.
  }
  my $capacity = $asset{$housingtype}{qtty} * $asset{$housingtype}{capacity};
  my $left = $capacity - (($housingtype eq "nursery") ? $asset{chick}{qtty} : ($asset{hen}{qtty} + $asset{rooster}{qtty}));
  my $needed = 0;
  debuglog(" ch: n=$n; ht=$housingtype; cap=$capacity; left=$left; needed=$needed");
  ## while ($left < $n) {
  ##   # TODO: This takes O(n) time; write an O(1) formula for it.
  ##   $needed++; $left += $asset{$housingtype}{capacity};
  ## }
  if ($left < $n) { # This should be faster.
    $needed = ($n - $left) / $asset{$housingtype}{capacity};
    if ($needed ne int $needed) {
      $needed = int($needed + 1);
    }}
  debuglog(" ch: n=$n; ht=$housingtype; cap=$capacity; left=$left; needed=$needed");
  # Simple case: if we already have the capacity, we're good:
  if ($needed == 0) {
    debuglog(" ch: returning $n");
    return $n;
  }
  # Failing that, can we autobuy the housing?
  my $value = $asset{$housingtype}{value} * $needed;
  debuglog(" ch: value=$value (and cash=$cash)");
  return if (not canafford($value)); # Cannot afford.
  if (not $asset{$housingtype}{asneeded}) {
    debuglog(" ch: cannot buy as needed");
    # We aren't buying as-needed, but make sure buying is unlocked:
    if (not $asset{$housingtype}{unlocked}{buy}{1}) {
      debuglog(" ch: unlocking manual buy for $housingtype");
      $asset{$housingtype}{unlocked}{buy}{1}++;
      push @message, ["You need more " . sgorpl(3, $asset{$housingtype}{name},
                                            $asset{$housingtype}{plural}) . ".", "assetneed"];
    }
    return;
  }
  if (canbuild($needed, $housingtype)) {
    debuglog(" ch: cb sez ok, rechecking cash ($cash) against value ($value)");
    return if not canafford($value); # In case buying the housing used up our funding.
    debuglog(" ch: building $needed $housingtype");
    buyasset($housingtype, $needed, $value, "canhouse");
    debuglog(" ch: returning $n");
    return $n;
  } else {
    debuglog(" ch: cb sez no.");
    return;
  }
}

sub canafford {
  my ($cost) = @_;
  return $cost if $cost < $cash;
  $cash -= $cost; # temporary, so bond sales don't trigger replacement bond purchases.
  for my $b (@bond) {
    if ($$b{mature}->ymd() lt $date->ymd()) {
      # Bond is mature.  Go ahead and sell it.
      sellbond($b);
      if ($cash >= 0) {
        $cash += $cost; # Restore what we took away,
        return $cash;   # and let the purchase proceed.
      }}}
  # If we get here, we can't cover the cost unless we sell bonds that aren't mature.
  if ($option{sellbonds} < 2) {
    $cash += $cost; # Restore what we took away,
    return;         # but the purchase cannot proceed.
  }
  for my $b (reverse @bond) {
    # reverse order means we sell the ones that are *not* about to mature, so that we don't lose all
    # our progress toward bond maturity every time we slightly overshoot our cash in hand.
    sellbond($b);
    if ($cash >= 0) {
      $cash += $cost; # Restore what we took away,
      return $cash;   # and let the purchase proceed.
    }}
  # We can't cover the purchase with sales of bonds that we own.
  # TODO: allow other financing methods, such as issuing bonds,
  #       if the player's credit rating is good enough.
  $cash += $cost; # Restore what we took away,
  return;         # but the purchase cannot proceed.
}

sub usedland {
  my $used;
  for my $atype (grep { $asset{$_}{landsize} } keys %asset) {
    $used += $asset{$atype}{qtty} * $asset{$atype}{landsize};
  }
  return $used;
}

sub canbuild {
  # Do we have enough space on our land to build these things?
  my ($number, $assetid) = @_;
  my $needland = $asset{$assetid}{size} * $number;
  my $usedland = usedland();
  my $haveland = $asset{acre}{qtty} * $asset{acre}{capacity};
  if ($usedland + $needland <= $haveland) {
    return $number; # Yep, got it covered.
  }
  # Don't have enough acreage.  Can we autobuy enough?
  my $acresneeded = 0;
  while ($usedland + $needland <= $haveland + ($acresneeded * $asset{acre}{capacity})) {
    # TODO: This takes O(n) time; write an O(1) formula for it.
    $acresneeded++;
  }
  my $value = $acresneeded * $asset{acre}{value};
  return if not canafford($value);
  if (not $asset{acre}{asneeded}) {
    # We aren't buying land as needed, but ensure buying it is unlocked:
    if (not $asset{acre}{unlocked}{buy}{1}) {
      $asset{acre}{unlocked}{buy}{1}++;
      push @message, ["You need more land to build on.", "assetneed"];
    }
    return;
  }
  # TODO: check licenses.
  if (buyasset("acre", $acresneeded, $value, "canbuild")) {
    return $number;
  }
  return;
}

##sub asset_cost {
##  my ($atype, $number) = @_;
##  my $total = 0;
##  my $stillneed = $number;
##  for my $q (reverse grep { $buyqtty{$_}{pmult}
##                          } (grep {
##                            $asset{$atype}{unlocked}{buy}{$_}
##                          } @{$asset{$atype}{buyqtty} || [1]})) {
##    my $n = int($stillneed / $buyqtty{$q}{number});
##    $total       += $n * $buyqtty{$q}{pmult} * $asset{$atype}{value};
##    $stillneeded -= $n * $buyqtty{$q}{number};
##  }
##  return $total;
##}

sub buyatleast { # If adequate funds are available, that is.
  my ($atype, $min, $blame) = @_;
  debuglog("buyatleast($atype, $min);");
  my $purchased = 0;
  my $stillneed = $min;
  for my $q (reverse grep { $buyqtty{$_}{pmult}
                          } (grep {
                            $asset{$atype}{unlocked}{buy}{$_}
                          } @{$asset{$atype}{buyqtty} || [1]})) {
    if ($stillneed > 0) {
      my $n = int($stillneed / $buyqtty{$q}{number});
      if ($n * $buyqtty{$q}{number} < $stillneed) { $n++; }
      my $price = $n * $buyqtty{$q}{pmult} * $asset{$atype}{value};
      debuglog(" bal: q=$q; n=$n; p=$price; c=$cash");
      if (canafford($price)) {
        debuglog(" bal: attempting to buy " . ($n * $buyqtty{$q}{number}) . ".");
        buyasset($atype, $n * $buyqtty{$q}{number}, $price, $blame);
        $purchased += $n * $buyqtty{$q}{number};
        $stillneed -= $n * $buyqtty{$q}{number};
      } else {
        debuglog(" bal: no can do, $price < $cash");
      }
    }
  }
  debuglog(" bal: fell short by $stillneed") if $stillneed > 0;
  return $purchased;
}

sub buyasset {
  my ($item, $number, $value, $blame) = @_;
  debuglog("buyasset($item, $number, $value);");
  return if not canafford($value);
  expendcash($value, (($blame eq "need") ? "essentials" : "purchases"),
             $asset{$item}{plural} || makeplural($asset{$item}{name}));
  addasset($item, $number);
  if (ref $asset{$item}{buyqtty}) {
    for my $q (@{$asset{$item}{buyqtty}}) {
      my $unlockat = $buyqtty{$q}{unlockqtty} || $buyqtty{$q}{number};
      if ($asset{$item}{qtty} >= $unlockat) {
        if ($buyqtty{$q}{number} eq "asneeded") {
          $asset{$item}{unlocked}{buy}{asneeded} ||= 1;
        }
        $asset{$item}{unlocked}{buy}{$buyqtty{$q}{id}} ||= 1;
        debuglog(" Unlocked buy-quantity '$q' ($buyqtty{$q}{id}) for $item.");
      }}}
  debuglog(" ba: bought $number, bringing total to $asset{$item}{qtty}.");
  return $number;
}

sub addasset {
  my ($id, $qtty) = @_;
  debuglog("addasset($id, $qtty);");
  $asset{$id}{qtty} += $qtty;
  trackage($id, $qtty, $date);
}

sub trackage {
  my ($assetid, $number, $when) = @_;
  return if not $asset{$assetid}{lifespan};
  my $expires = $when->clone()->add( %{$asset{$assetid}{lifespan}} );
  my ($group) = grep {
    $$_{year} == $expires->year() and $$_{month} == $expires->month()
  } @{$asset{$assetid}{agegroup} || +[]};
  if ($group) {
    $$group{qtty} += $number;
  } else {
    push @{$asset{$assetid}{agegroup}},
      +{ expire => $expires->ymd(), # Actual date of expiration
         year   => $expires->year(),   # Used for fuzzy matching, to
         month  => $expires->month(),  # keep the number of groups low.
         qtty   => $number,
         since  => $when->ymd(),
       };
  }
}

sub generate_world {
  my ($parent) = @_;
  debuglog(qq[generate_world()]);
  # TODO: even larger jurisdictions?
  my ($extant) = grep { not $$_{licensed} } @world;
  return $extant if $extant;
  my $parent ||= undef;
  my $name; while ((not $name) or grep { lc($$_{name}) eq lc($name) } @extantplace) {
    $name = ucfirst randomplaceword();
    if (25 > rand 100) {
      $name = join " ", $name, randomplaceword();
    }}
  my $capital = generate_placename(city_prefix(), city_suffix());
  debuglog(qq[World will be $name, global capital will be $capital]);
  push @extantplace, +{ type   => "municipality",
                        name   => $capital,
                        parent => $name,
                      };
  push @extantplace, +{ type   => "world",
                        name   => $name,
                        parent => $parent,
                      };
  my $w = +{ size        => 1 + int rand 1000, # number of nations in this world
             nations     => 0, # number generated so far
             name        => $name,
             capital     => $capital,
             capitalword => "Global Capital",
             parent      => $parent,
           };
  push @world, $w;
  debuglog(qq[There are now ] . @world . qq[ worlds in the known universe.]);
  return $w;
}

sub generate_nation_name {
  my $basename = undef;
  while ((not defined $basename) or
         grep { lc($$_{name}) eq lc($basename) } @extantplace) {
    $basename = join ((95 > rand 100) ? " " : " and "),
      map { ucfirst randomplaceword() } 1 .. (1 + int rand rand 3);
  }
  $basename ||= ucfirst randomplaceword();
  if (6 > rand 100) {
    return $basename;
  } elsif (17 > rand 100) {
    my @basemod = ((("the") x 10),
                   "Greater", "Lesser", "Middle", "Upper", "Lower",
                   "North", "South", "East", "West",
                   "Northern", "Southern", "Eastern", "Western", "Central",
                  );
    # TODO: at low probability, randomword + -ese or -ite or -ic or whatnot, as in
    #       Islamic Republic, Hashemite Kingdom, etc.
    $basename = join " ", ($basemod[rand @basemod], $basename);
    if (5 > rand 100) {
      return ucfirst $basename;
    }}
  my @modifier = ("People's", "United", ((50 > rand 100) ? "Free" : "Grand"), "Democratic",
                  "National", ((65 > rand 100) ? "Federal" : "Federated"),
                  "Representative",
                  "Socialist");
  my @type = (((("Republic") x 30),
               (("Commonwealth") x 5),
               (("Principality") x 5),
               (("Union") x 5),
               (("Kingdom") x 4),
               (("Federation") x 4),
               (("Confederacy") x 3),
               (("Confederation") x 3),
               (("Nation") x 3),
               (("Domain") x 2),
               (("State") x 2),
               "Alliance", "Association", "Coalition", "Society", "Syndicate", "Dominion",
               "Empire", "Sovereignty", "Suzerainty", "Emirate", "Realm", "Duchy", "Monarchy",
               "Motherland", "Fatherland", "Homeland",
               ((50 > rand 100) ? "Islands" : "Island"), "Archipelago",
              ) x 3,
              "Colony", "Crown Colony", "Mandate", "Country", "Nation State", "Dependency",
              "Territory", "Sultanate", "Dictatorship", "Tyrrany",
             );
  # TODO: at VERY low probability, join up multiple types, as in "Republic of the Union of"
  my $typename = $type[rand @type];
  if (5 > rand 100) {
    $typename = makeplural($typename);
  }
  my @mod = ();
  for (0 .. int rand rand 6.5) {
    push @mod, $modifier[int rand @modifier];
  }
  @mod = uniq(@mod);
  if (12 > int rand 100) {
    @mod = randomorder(@mod);
  }
  # TODO: at low probability, instead of "Modified Foo of Ubbledubgong" do something more like
  #       "Modified Ubbledubgongese Foo"
  return join " ", (@mod, $typename, "of", $basename);
}

sub generate_nation {
  my ($world) = @_;
  debuglog(qq[generate_nation()]);
  my ($extant) = grep { not $$_{licensed} } @nation;
  return $extant if $extant;
  if (not @world) {
    generate_world();
  }
  $world ||= $world[0];
  #debuglog(Dumper(+{ world_array => \@world,
  #                   this_world  => $world }));
  debuglog(qq[generate_nation(): locating nation on $$world{name}]);
  # TODO: require that the world have "size" for another nation
  #       (i.e., don't license the player to operate in more nations
  #        than exist in the world; require global licenses as needed)
  my $name = generate_nation_name();
  my $capital = generate_placename(city_prefix(), city_suffix());
  debuglog(qq[generate_nation(): nation will be $name, with the capital at $capital]);
  my @provincesuffix = (((" Province") x 30),
                        (("") x 20),
                        ((" Prefecture", " State") x 3),
                        " Area", " Territory", " Sweep", " Fiefdom", " Bailiwick", " Realm",
                        " Region", " Canton",
                       );
  push @extantplace, +{ type   => "municipality",
                        name   => $capital,
                        parent => $name,
                      };
  push @extantplace, +{ type   => "nation",
                        name   => $name,
                        parent => $$world{name},
                      };
  # TODO: assign min and max nation sizes inversely to world size
  my $n = +{ size         => 5 + int rand rand rand 75, # size in provinces
             provinces    => 0, # number generated so far
             name         => $name,
             capital      => $capital,
             capitalword  => "Capital",
             provincesuff => $provincesuffix[rand @provincesuffix],
             parent       => $$world{name},
           };
  push @nation, $n;
  debuglog(qq[Each province will be called a $$n{provincesuff}.\n  There are now ] . @nation . " nations.");
  return $n;
}

sub generate_province {
  my ($nation) = @_;
  debuglog(qq[generate_province()]);
  my ($extant) = grep { not $$_{licensed} } @province;
  return $extant if $extant;
  if (not @nation) {
    generate_nation();
  }
  $nation ||= $nation[0];
  debuglog(qq[generate_province(): locating province in $$nation{name}]);
  # TODO: require that the nation have "size" for another province
  #       (i.e., don't license the player to operate in more provinces
  #        than the nation has; require national licenses as needed)
  my $name    = generate_placename("", $$nation{provincesuff});
  my $capital = generate_placename(city_prefix(), city_suffix());
  my $csuff   = county_suffix();
  debuglog(qq[generate_province(): province will be $name, with a capital at $capital]);
  push @extantplace, +{ type   => "municipality",
                        name   => $capital,
                        parent => $name,
                      };
  push @extantplace, +{ type   => "province",
                        name   => $name,
                        parent => $$nation{name},
                      };
  my $p = +{ size        => 4 + int rand rand 60, # size in counties
             counties    => 0, # number generated so far
             # TODO: some nations should have larger min and max province sizes than other nations.
             name        => $name,
             capital     => $capital,
             capitalword => "Capital",
             countysuff  => $csuff,
             parent      => $$nation{name},
           };
  push @province, $p;
  debuglog(qq[generate_province(): Each county will be called a $$p{countysuff}.  There are now ]
           . @province . qq[ provinces.]);
  return $p;
}

sub generate_county {
  my ($province) = @_;
  debuglog(qq[generate_county()]);
  my ($extant) = grep { not $$_{licensed} } @county;
  return $extant if $extant;
  if (not $province) {
    ($province) = (grep { $$_{counties} < $$_{size} } @province);
  }
  $province ||= generate_province();
  debuglog(qq[generate_county(): will generate a new county in $$province{name}.]);
  # TODO: require that the province have "size" for another county
  #       (i.e., don't license the player to operate in more counties
  #        than the province has; require province licenses as needed)
  my $name = generate_placename(county_prefix(), $$province{countysuff});
  my $seat = generate_placename(city_prefix(), city_suffix());
  my $size = int(15000 + ((1 + rand 15000) * (1 + rand 25) * (1 + rand 100)));
  my $land = int((1 + rand (sqrt($size))) * (1 + rand(sqrt($size))));
  my $mult = ((50 > rand 100)
              ? 1 + (((rand 5) || 1) * ((rand 2) || 0.1) * ((rand 2) || 0.25))
              : ((100 - (((rand 5) || 1) * (rand(5) || 0.1) * (rand(3) || 0.2))) / 100));
  push @extantplace, +{ type   => "municipality",
                        name   => $seat,
                        parent => $name,
                      };
  push @extantplace, +{ type   => "county",
                        name   => $name,
                        parent => $$province{name},
                      };
  my $c = +{ name           => $name,
             capital        => $seat,
             capitalword    => "County Seat", # TODO: some larger jurisdictions may use a different term.
             size           => $size, # Total size of the county, in acres.
             owned_land     => 0,     # Number of acres the player already owns.
             available_land => $land, # Number of acres the player can potentially purchase.
             landcost       => int($asset{acre}{value} * $mult),
             parent         => $$province{name},
           };
  debuglog(qq[generate_county(): generated $$c{name} (in $$c{parent}) with $$c{capitalword} at $$c{capital}, $$c{available_land}/$$c{size} acres available at $$c{landcost}zm.]);
  push @county, $c;
  return $c;
}
sub common_surnames {
  # Note: try to avoid duplicating the ones in common_placenames()
  return ("Alexander", "Allen", "Alvarado", "Alvarez", "Anderson", "Andrews", "Armstrong", "Arnold",
          "Austin", "Bailey", "Baker", "Barnes", "Bell", "Benedict", "Bennett", "Berry", "Bishop",
          "Bjarne", "Boyd", "Burns", "Brooks", "Bradley", "Brown", "Bryant", "Burke", "Burton",
          "Butler", "Campbell", "Carleson", "Carpenter", "Carr", "Carroll", "Carter", "Castellucci",
          "Castillo", "Chan", "Chapman", "Chavez", "Chen", "Clark", "Cohen", "Cole", "Coleman",
          "Collins", "Cook", "Cooke", "Cooper", "Costello", "Cox", "Crawford", "Cruz", "Cunningham",
          "Daniels", "Davis", "Dean", "Delgado", "Diaz", "Dixon", "Duncan", "Dunn", "Dyson", "Eady",
          "Eddy", "Edwards", "Elder", "Elkins", "Elliott", "Ellis", "Estrada", "Evans", "Farner",
          "Farnsworth", "Faust", "Ferguson", "Fernandez", "Fischer", "Flores", "Foster", "Foust",
          "Fox", "Freeman", "Fuchs", "Fuller", "Garcia", "Gardner", "Gibbs", "Gibson", "Gilbert",
          "Gomez", "Gonzales", "Gordon", "Graham", "Grassi", "Gray", "Griffin", "Guzman", "Hall",
          "Hamilton", "Hansen", "Harper", "Harris", "Hardt", "Harvey", "Hawkins", "Henderson",
          "Hernandez", "Herrera", "Hill", "Hoffman", "Holmes", "Howard", "Howell", "Hoying",
          "Hudson", "Hughes", "Humrichouser", "Hunt", "Jacobs", "Jacobson", "James", "Jenkins",
          "Jensen", "Jimenez", "Johns", "Johnson", "Jones", "Jordan", "Kaplan", "Kelly", "Kim",
          "Kirk", "Knight", "Larson", "Lawrence", "Lawson", "Layne", "Lewis", "Long", "Lopez",
          "Louis", "Lucas", "Lynch", "Maldonaldo", "Martin", "Martinez", "Mason", "Matthews",
          "McCoy", "McCready", "McDonald", "MacElligott", "MacIntyre", "Medina", "Meijer",
          "Menendez", "Mendoza", "Meyer", "Miller", "Mills", "Mitchell", "Montgomery", "Moore",
          "Morales", "Moreno", "Morgan", "Morris", "Morrison", "Murphy", "Murray", "Myers",
          "Nichols", "Nguyen", "O'Brien", "Okoje", "Olson", "Olusola", "Ortega", "Ortiz",
          "O'Reilly", "Owens", "Palmer", "Park", "Parker", "Patel", "Patterson", "Payne",
          "Pennington", "Perez", "Perkins", "Perry", "Peters", "Peterson", "Phillips", "Porter",
          "Powell", "Price", "Ramirez", "Ramos", "Ramsay", "Rawlins", "Ray", "Reed", "Reyes",
          "Reynolds", "Richards", "Richardson", "Riley", "Rivera", "Roberts", "Robertson",
          "Robinson", "Rodriguez", "Rogers", "Romero", "Rose", "Ross", "Ruiz", "Rupp", "Russell",
          "Ryan", "Salazar", "Sallee", "Sanchez", "Sanders", "Sandoval", "Santiago", "Santos",
          "Schiller", "Schmidt", "Schultz", "Schuman", "Scott", "Shaw", "Short", "Shuck", "Silver",
          "Simmons", "Simpson", "Singh", "Smith", "Snyder", "Soto", "Spayde", "Spencer", "Stein",
          "Stephens", "Stevens", "Stewart", "Stone", "Sullivan", "Thomas", "Thompson", "Tucker",
          "Torres", "Turner", "Vargas", "Vasquez", "Vega", "Wagner", "Wakim", "Walker", "Wallace",
          "Ward", "Warren", "Waterson", "Watkins", "Watson", "Weaver", "Webb", "Weber", "Welch",
          "Wells", "Wheeler", "White", "Williams", "Willis", "Wright", "Young", "Zed");
}

sub common_placenames {
  return ("Lincoln", "Franklin", "Clinton",
          "George", "Elizabeth", "Virginia", "Victoria", "Henry",
          "Chester", "Marion", "Bristol", "Dover", "Salem", "Win", "Mil", "Milton",
          "Lebanon", "Alexandria", "Antioch", "Berlin", "Birmingham", "Athen", "Blooming",
          "Paris", "Cairo", "Burling", "Vernon", "Cleveland", "Hudson", "Beacon",
          "Spring", "Summer", "Winter", "Love", "Day", "Man", "Ox", "New",
          "Clay", "Sand",  "Ash", "Burn",
          "Farm", "Farmer", "River", "Rivers", "King", "Kings", "Castle",
          "Green", "Black", "White", "Red", "Blue", "Grey", "Dark", "Light", "Hard", "Soft",
          "Washington", "Adams", "Jefferson", "Madison", "Monroe", "Harrison",
          "Taylor", "Tyler", "Pierce", "Hayes", "Garfield", "Arthur",
          "Roosevelt", "Wilson", "Harding", "Hoover", "Kennedy", "Ford", "Reagan",
          "Vanderbilt", "Carnegie", "Rockefeller", "Buffett", "Jacobs",
          "Nelson", "Lee", "Grant", "Jackson", "Sherman",
          "Patton", "MacArthur", "Marshall", "Pershing",
          "Euler", "Kline", "Gauss", "Euclid", "Bernoulli", "Newton", "Lowe",
          "Torvalds", "Wall", "Knuth", "Raymond", "Ritchie", "Kernighan",
          "Oak", "Maple", "Hazel", "Hickory", "Pine", "Spruce",
          "Pleasant", "Good", "Right", "Center", "Fair", "Wood",
         );
}

sub generate_placename {
  my ($prefix, $suffix) = @_;
  my ($basename, @option);
  debuglog(qq[generate_placename()]);
  my $userpw = 0;
  my $maxtries = 50;
  if (70 > rand 100) {
    # Try to pick a common placename:
    @option = @commonplacename;
    if ($suffix eq "ton") {
      push @option, $_ for (qw(Arling Lexing Ea Middle Nor));
      @option = map { s/t$//; $_ } @option;
    }
  } elsif (30 > rand 100) {
    @option = @commonsurname;
  } else {
    $userpw = 1;
    while (($maxtries * 2) > scalar @rpw) {
      push @rpw, randomplaceword();
    }
    @option = @rpw;
  }
  debuglog(qq[generate_placename(): ] . @option . qq[ options to pick from.]);
  my $tries = 0;
  while (((not $basename) or (grep { lc($$_{name}) eq lc($basename) } @extantplace) or
          (index(lc($basename), lc($suffix)) > 0) or
          (index(lc($basename), lc($prefix)) > 0))
         and ($tries < $maxtries)) {
    $basename = $option[int rand @option];
    if ($userpw) {
      @rpw = grep { not $_ eq $basename } @rpw;
    }
    if (5 > rand 100) {
      my @joiner = ("", " ", "-");
      $basename = join $joiner[rand @joiner], $option[int rand @option];
    }
    $tries++;
  }
  debuglog(qq[generate_placename(): returning after $tries tries.]);
  return $prefix . $basename . $suffix;
}
sub city_prefix {
  return "" if 60 > rand 100;
  if (not @city_prefix) {
    @city_prefix = ("North ", "South ", "East ", "West ",
                    "New ", "New ", "New ", "Old ",
                    "Port ", "Mount ", "Royal ", "Pleasant ", "Fair ",
                   );
  }
  debuglog(qq[city_prefix(): choosing from ] . @city_prefix . " options.");
  return $city_prefix[int rand @city_prefix];
}
sub commonplacewordsuffixes {
  return ("field", "port", "land", "haven", "gate", "crest", "fair",
          "chester", "castle", "bank", "dale", "hurst");
}
sub city_suffix {
  return "" if 50 > rand 100;
  my @option;
  if (not @city_suffix) {
    @city_suffix = map { (($_) x 10) } (qw(ton ton berg sberg burg ville town ia s side ford));
    push @city_suffix, $_ for (commonplacewordsuffixes(),
                               " Valley", " Lake", " Beach", " Falls", " Wood", " City", " Junction",
                               " Harbor", " Point", " Heights", " Hills", " Landing", " Center", " Grove");
  }
  my @option = @city_suffix;
  for my $maybe ("view", " Park", " Pier", " Road", " Ford", " Township", " Village", " Mesa",
                 " Flats", " Gorge", " Canyon", " Cliffs",
                 "home", "house") {
    push @option, $maybe if 30 > rand 100;
  }
  debuglog(qq[city_suffix(): choosing from ] . @option . " options.");
  return $option[int rand @option];
}
sub county_prefix {
  return ""; # TODO
}
sub county_suffix {
  debuglog(qq[county_suffix()]);
  if (not scalar @county_suffix) {
    @county_suffix = (((" County") x 80),
                      ((" Parish", " Borough", "shire", " Shire", "") x 10),
                      ((" Section", " District", " Division", " MSA", " Precinct",
                        " Confine", " Jurisdiction") x 3),
                      " Purview", " Barony", " Zone", " Demesne",
                      " Duty", " Holding", " Tract", "shire County",
                     );
  }
  return $county_suffix[int rand @county_suffix];
}

sub randomplaceword {
  my @syllable = map { randomsyllable() } 1 .. 2 + (int(rand 2) * (rand 2) * (rand 2));
  if ((4 > scalar @syllable) and (40 > rand 100)) {
    my @suffix = ("er", "er", "er", "er", "ing", "ing", "ing",
                  "a", "ia", "ac", "in", "en", "on", "ie", "ish",
                  "le", "lisle", "son", "ham", "ona", "ora", "kirk",
                  "berg", "burg", "bury", "borough", "by", "land", "pont",
                  "ick", "stead", "aide", "ette", "thwaite", "thorpe",
                  commonplacewordsuffixes(),
                 );
    push @syllable, $suffix[int rand @suffix];
  }
  my $word = join "", @syllable;
  $word =~ s/(.)\1\1/$1$1/g;
  return ucfirst $word;
}
sub randomsyllable {
  my @initial = (qw(b b b b b b br bl c c c ch cl cr chr d d d d d dr dl f f f
                    fr fl g g gh gr gl h j k k k l l l m m m m n n n n
                    p p p pr pl ph pf qu r r r r r r r
                    s s s s s s sh sc sch st st st str str sk sl sm sn sn sp sw sz
                    t t t t t t t t tr tr tr tr th th th thr v w w y z),
                 "", "", "", "", "", "", "");
  my @vowel   = (qw(a e i o u a e i o u a e i o u a a a e e e i i o o o
                    a e i o u a e i o u a e i o u a a a e e e i i o o o
                    ai ae au ea ee ei ia ie oa oe oi oi oo oo oo y ui
                    ay oy aw ew ow ow));
  my @final   = (qw(b b b b b rb cc ch rch lch nch ck ck ck d d d d
                    nd rd ld ff ff lf rf g g gg gh h k k k l l l ll ll
                    m m m m mm mm rm lm n n n n nn nn nn rn ln
                    p p pp pp lp rp np r r r r rr rr
                    s s s s s s ss ss ss sh sh rsh lsh rs ls ns gs cs
                    t t t t tt tt tt rt rt st st rst mt pt ft nt nt ct
                    v vv lv rv th th th rth lth phth mth x x z zz zh),
                 "", "", "", "", "", "", "");
  return $initial[int rand @initial] . $vowel[int rand @vowel] . $final[int rand @final];
}

sub coverbaddebt {
  if (($asset{acre}{qtty} > 1) and ($cash < 0)) {
    my $priceper = int($asset{acre}{value} * 2 / 3); # You don't get full price.
    my $mustsell = int((0 - $cash) / $priceper);
    # We've truncated down, which means you can be left with a
    # negative balance, but it'll be less than the price of an acre
    # of land, so in the grand scheme of things not that much.
    # We're gonna just say the bank will float you that amount.
    if ($mustsell >= $asset{acre}{qtty}) {
      gameover("You are unable to cover your debts.  The bank forecloses on your land.");
    }
    # Ok, so we do *have* enough land that we can sell some, cover
    # our debts, and still have something left.
    if ($mustsell > 0) {
      $asset{acre}{qtty} -= $mustsell; # ouch
      gaincash(($mustsell * $priceper), "sales", "land");
      push @message, ["You sell off " . shownum($mustsell) . " "
                      . sgorpl($mustsell, "acre", "acres")
                      . " of land to cover your debts.", "assetloss"];
    }
    # But what all is *on* the land we must sell, that we will lose
    # in the process?
    my $used = usedland();
    my $have = $asset{acre}{qtty} * $asset{acre}{capacity};
    while ($used > $have) {
      for my $atype (grep {
        $asset{$_}{landsize} and ($asset{$_}{qtty} > ($asset{$_}{minqtty} || 0))
      } keys %asset) {
        my $hogsland = ($asset{$atype}{qtty} * $asset{$atype}{landsize}) / $used;
        # hogsland is a floating point representation of how much of
        # the used land this asset is using.  To decide how much to
        # sell, we multiply that number by the amount of land-overuse,
        # and try to free that much land by selling some of this asset.
        my $freeup  = $hogsland * ($used - $have);
        my $selloff = $freeup / $asset{$atype}{landsize};
        if ($selloff ne int $selloff) {
          $selloff = int($selloff + 1);
        }
        $asset{$atype}{qtty} -= $selloff;
        gaincash($selloff * $asset{$atype}{resale}, "sales", $asset{$atype}{name})
          if $asset{$atype}{resale};
        # Things like chicken coops can't be sold off; they just get
        # torn down by the land's new owner.  But feed factories are
        # worth more than the land they're built on, and you recover
        # some of that value.
      }
      $used = usedland();
    }
    # And so now there's the question of how many chickens we can
    # still house.  We're not going to give the player messages about
    # this because they're already getting messages about selling off
    # the land, and we don't want to fill up the whole message area
    # with what basically amounts to a single event, however
    # traumatic.  Also, some players will want to imagine that the new
    # land owners are keeping the chicken coops and nurseries and
    # letting the chickens live out their days, and if we tell them
    # it's all going into a giant chipper-shredder to make room for
    # a golf course, it will make them sad.  We wouldn't want that.
    # Anyway, the chicks are straightforward...
    if ($asset{chick}{qtty} > ($asset{nursery}{qtty} * $asset{nursery}{capacity})) {
      degroup_chickens("chick", ($asset{chick}{qtty} - ($asset{nursery}{qtty} * $asset{nursery}{capacity})));
    }
    # Now about those adult chickens...
    my $nixadults = ($asset{hen}{qtty} + $asset{rooster}{qtty}) -
      ($asset{coop}{qtty} * $asset{coop}{capacity});
    if ($nixadults > 0) {
      my $nixroosters = int($nixadults * ($asset{rooster}{qtty} / ($asset{rooster}{qtty} + $asset{hen}{qtty})));
      my $nixhens = $nixadults - $nixroosters;
      degroup_chickens("rooster", $nixroosters);
      degroup_chickens("hen", $nixhens);
    }
  }
}

sub degroup_chickens {
  my ($atype, $nix) = @_;
  # We take the oldest ones first.  This is merciful to the player
  # when doing adult chickens, less so when doing chicks, but in
  # any case it's _simplest_, because we can just process groups
  # in the order in which they were added, i.e., oldest first.
  my @grp = @{$asset{chick}{agegroup} || +[]};
  my $degrouped = 0;
  while (($nix > 0) and @grp) {
    my $g = shift @grp;
    my $kill = $$g{qtty};;
    $kill = $nix if $kill > $nix;
    $$g{qtty} -= $kill;
    $asset{$atype}{qtty} -= $kill;
    $degrouped += $kill;
  }
  $asset{$atype}{agegroup} = [grep { $$_{qtty} > 0 } @{$asset{$atype}{agegroup}}];
  return $degrouped;
}

sub expendcash {
  my ($amount, $type, $subcat) = @_;
  $cash -= $amount;
  trackcashflow($amount, $type, $subcat);
  if ($cash < 0) {
    my ($soldmature, $soldimmature, $soldacre) = (0,0,0);
    my @maturebond = grep { $$_{mature}->ymd() le $date->ymd() } @bond;
    while ((scalar @maturebond) and ($cash < 0)) {
      my $b = shift @maturebond;
      sellbond($b);
    }
    if (($cash < 0) and ($creditrating >= 1)) {
      my $loans = int((($loanamount - 1) - $cash) / $loanamount);
      # TODO: limit how many loans you can take out, based on $creditrating
      $debt += $loans;
      $cash += ($loans * $loanamount);
    }
    # If we can't borrow any more, then we must sell off bonds, even
    # if they are not mature, to cover the debt.
    while ((scalar @bond) and ($cash < 0)) {
      my $b = pop @bond;
      sellbond($b);
    }
    if ($cash < 0) {
      coverbaddebt(); # try to avoid this, it is painful
    }
  }
}

sub gaincash {
  my ($amount, $type, $subcat) = @_;
  # The type will  generally be sales in  the early game, but  in later phases there  can be capital
  # gains from other sources.
  trackcashflow($amount, $type, $subcat);
  $cash += $amount;
  # Percentage-based budget categories, go:
  for my $bk (grep { $budget{$_}{value} =~ /[%]$/ } keys %budget) {
    my ($pct) = $budget{$bk}{value} =~ /(\d+)[%]/;
    my $budgetamt = int($amount * $pct / 100);
    if (ref $budget{$bk}{gain}) {
      $budget{$bk}{gain}->($budgetamt);
    } else {
      expendcash($budgetamt, "budget", $budget{$bk}{name}) if $budgetamt;
    }
  }
  while ($cash > $investcashover) {
    buybond();
  }
}

sub sellbond {
  my ($b) = @_;
  croak "sellbond(): what bond?  " . Dumper($b) if not ref $b;
  my $amt = $$b{amount};
  if ($$b{mature}->ymd() le $date->ymd()) {
    my $term = $$b{mature}->year() - $$b{issued}->year();
    $amt = int interest($amt, $$b{rate}, $term);
  }
  $$b{id} = "__SOLD__";
  gaincash($amt, "investment", "bonds");
  @bond = grep { $$_{id} ne "__SOLD__" } @bond;
}

sub buybond {
  my ($amt, $issuer, $rate, $term) = @_;
  $amt ||= $defaultbondamt;
  return if $amt >= ($cash * 1.1);
  $issuer ||= "Federal Government";
  # TODO: model a changing prime rate based on simple macroeconomic modeling.
  $rate ||= 1.5; # This is the Annual Percentage Rate (i.e., it gets divided by 100 when doing calculations).
  $term ||= 30 * 12;
  my $issued = $date->clone();
  my $mature = $issued->clone()->add( months => $term );
  expendcash($amt, "investment", "bonds");
  my $b = +{ issuer => $issuer,
             amount => $amt,
             issued => $issued,
             mature => $mature,
             rate   => $rate,
             id     => ($date->year() . (sprintf "%02d%02d", $date->month(), $date->mday()) . int rand (32767 * 32767)),
           };
  push @bond, $b;
  return $b;
}

sub trackcashflow {
  my ($number, $category, $subcategory) = @_;
  $cashflow{current}{$category}  += $number;
  $cashflow{year}{$category}     += $number;
  $cashflow{total}{$category}    += $number;
  if ($subcategory) {
    $cashflow{sc}{current}{$category}{$subcategory}  += $number;
    $cashflow{sc}{year}{$category}{$subcategory}     += $number;
    $cashflow{sc}{total}{$category}{$subcategory}    += $number;
  }
}

sub interest {
  my ($principal, $rate, $term) = @_;
  # The rate should be the _percentage_ rate, so e.g. 2.5 for 2.5% interest.
  # The rate and term must use the same time unit, e.g., they can both be per annum.
  # The result will NOT be rounded or truncated; the caller must do that if desired.
  return 0 if not $principal;
  return $principal if not $rate;
  return $principal if not $term;
  my $e = 2.718281828459; # "My hamster I exploded by grenades.  I exploded it brutally, with anger, willfully."
  my $rt = $term * $rate / 100;
  return $principal * ($e ** $rt);
}

sub adjust_primerate {
  # TODO: do simple economic modeling so that prime rate changes follow reasonable patterns.
  # For now, just do random adjustments:
  my $numerator   = 100 + rand 5;
  my $denominator = 100 + rand 5;
  my $p = $primerate * $numerator / $denominator;
  return 1 if $p < 1;
  return 5 if $p > 5;
  $primerate = $p;
}

sub updatetopbar {
  my ($w) = @_;
  my ($now); eval {
    $now = DateTime->now( time_zone => ($option{localtimezone} || "UTC") );
  }; croak "DateTime problem in updatetopbar()" if not ref $now;
  my $dtext = $date->year() . " " . $date->month_abbr() . " " . $date->mday()
    . " " . $date->day_abbr()
    . ($paused ? " PAUSED" : "");
  my $ttext = $now->hour() . ":" . sprintf("%02d", $now->minute());
  my $title = "Eggs v" . $version;
  $$w{text} = join("", map { " " } 0 .. $xmax);
  substr($$w{text}, 1, length($dtext), $dtext);
  substr($$w{text}, $xmax - length($ttext) - 1, length($ttext), $ttext);
  substr($$w{text}, int(($xmax / 2) - (length($title) / 2)), length($title), $title);
}

sub toggle_pause {
  my ($force) = @_;
  if ($paused and not $force) {
    $paused = undef;
    push @message, ["Resumed.", "meta"];
  } else {
    $paused = 1;
    push @message, ["Paused.", "meta"];
  }
}

sub writepricelist {
  my ($filename) = @_;
  $filename ||= "price-chart.txt";
  my (%packagemin, %packagemax, %numincluded);
  my %basicunit = ( "feed" => " / bag",
                    "egg"  => " each");
  my @note;
  my @entry = map {
    my ($product, $label, $id, $nsub, $subunit, $pkg, $retailmult) = @$_;
    #print "writepricelist(): evaluating $product by $label <$id> / $nsub / $subunit / $pkg\n";
    my $value = $asset{$id}{value} || "?";
    my ($pkgmin, $pkgmax);
    if (defined $pkg) {
      for my $q (grep { $_ ne "asneeded" } @{$asset{$pkg}{buyqtty}}) {
        my $number = $buyqtty{$q}{number}; die "invalid number, '$number'" if not ($number > 0);
        my $pmult  = $buyqtty{$q}{pmult} || 1;
        my $total  = $asset{$pkg}{value} * $pmult;
        my $per    = $total / $number;
        if ($per > $value) {
          push @note, "$product sells for more than its value when sold by the " . ($buyqtty{$q}{name} || $q)
            if $pkgmax ne $value;
        }
        if ((not defined $pkgmin) or ($per < $pkgmin)) {
          $pkgmin = $per;
        }
        if ((not defined $pkgmax) or ($per > $pkgmax)) {
          $pkgmax = $per;
        }
      }
    }
    $pkgmin ||= 0;
    $pkgmax ||= 0;
    if (defined $subunit) {
      $pkgmin += ($packagemin{$subunit} || 0);
      $pkgmax += ($packagemax{$subunit} || 0);
    }
    $packagemin{$id} = $pkgmin;
    $packagemax{$id} = $pkgmax;
    my $number = (defined $subunit) ? (($numincluded{$subunit} || 1) * $nsub) : 1;
    $numincluded{$id} = $number;
    my $totalvalue = ($value + 0) ? ($value + ($pkgmin || 0)) : "?";
    my $costperunit = $number ? (($totalvalue + 0) ? (sprintf "%0.2f", ($totalvalue / $number)) : "?") : "E";
    my $retail = ($asset{$id}{retail})
      ? ($asset{$id}{retail} . " (" . (sprintf "%0.2f", $asset{$id}{retail} / $number) . $basicunit{$product} . ")")
      : ($retailmult ? (($retailmult * $number) . " (" . $retailmult . "$basicunit{$product})") : "?");
    [$label, $number, $value, (($pkgmin || $pkgmax) ? (sprintf "%0.2f - %0d", $pkgmin, $pkgmax) : "N/A"), (sprintf "%0.2f", $totalvalue), $costperunit, $retail];
  } (["egg", "Egg",            "egg",          undef, undef,           undef,            50 ],
     ["egg", "Dozen (Carton)", "dozen",           12, "egg",           "carton",         20 ],
     ["egg", "Gross (Case)",   "gross",           12, "dozen",         "case",           18],
     ["egg", "Pallet",         "palletload",      45, "gross",         "emptypallet",    15],
     ["egg", "Container",      "containerload",   24, "palletload",    "emptycontainer", 12],
     ["egg", "Freighter",      "panamaxload",   6500, "containerload", "emptyfreighter", 10],
     ["egg", "POD",            "podload",       1024, "panamaxload",   "emptypod"],
     ["feed", "Feed Bag",      "feedbag",      undef, undef,           "emptybag",       $asset{chickenfeed}{value} * $buyqtty{feedbag}{pmult}],
     ["feed", "Pallet",        "feedpallet",      25, "feedbag",       "emptypallet",    $asset{chickenfeed}{value} * $buyqtty{feedpallet}{pmult}],
     ["feed", "Container",     "feedcontainer",   24, "feedpallet",    "emptycontainer"],
     ["feed", "Freighter",     "feedfreighter", 6500, "feedcontainer", "emptyfreighter"],
     ["feed", "POD",           "feedpod",       1024, "feedfreighter", "emptypod"],
    );
  unshift @entry, ["-------", "-", "-----", "--------", "-----", "---------", "------------"];
  unshift @entry, ["Product", "#", "Value", "Pkg Cost", "Total", "Cost/Unit", "Retail Price"];
  for my $colno (0 .. 5) {
    my $maxwidth = 0;
    #print "writepricelist(): finding max width of column $colno\n";
    for my $row (@entry) {
      #print " * checking entry: '$$row[$colno]'\n";
      my $w = length($$row[$colno]);
      $maxwidth = $w if $w > $maxwidth;
    }
    for my $row (@entry) {
      while (length($$row[$colno]) < $maxwidth) {
        $$row[$colno] = " " . $$row[$colno];
      }
    }
  }
  open LST, ">", $filename;
  for my $row (@entry) {
    print LST join " ", @$row;
    print LST "\n";
  }
  close LST;
}

sub abbreviate_stockname {
  my ($name) = @_;
  my @letter = grep { /([A-Z])/i } split //, $name;
  my @uclett = grep { $_ eq uc $_ } @letter;
  my @lclett = grep { $_ eq lc $_ } @letter;
  if (4 == scalar @uclett) {
    return join "", @uclett;
  }
  while (3 < scalar @uclett) {
    my @l = map { [$_ => rand 100] } @uclett;
    my $max = 0;
    for my $char (@l) {
      $max = $$char[1] if $max < $$char[1];
    }
    @uclett = map { $$_[0] } grep { $$_[1] ne $max } @l;
  }
  while (3 > scalar @uclett) {
    my $char = uc $lclett[rand @lclett];
    push @uclett, $char;
  }
  return join "", @uclett;
}

sub stockquality {
  my ($symbol) = @_;
  my $sq = log($stock{$symbol}{sales} || 1);
  my $aq = log($stock{$symbol}{assets} || 1);
  my $cq = log($stock{$symbol}{cash} || 1);
  my $dq = log($stock{$symbol}{debt} || 1);
  return int((2 * $sq) + $aq + $cq - $dq);
}

sub describestock {
  my ($symbol) = @_;
  my $quality = stockquality($symbol);
  my $qualdesc =
    ($quality > 80) ? "an amazing" :
    ($quality > 70) ? "a leading" :
    ($quality > 60) ? "an innovative" :
    ($quality > 50) ? "a sturdy" :
    ($quality > 40) ? "a" :
    ($quality > 30) ? "an underdog" :
    "a slightly dodgy";
  my $oshares = int($stock{$symbol}{shares} - $stock{$symbol}{owned});
  #my ($i) = grep { $$_{industry} eq $stock{$symbol}{industry} } @industry;
  return $stock{$symbol}{name} . qq[ ($symbol) is ] . $qualdesc . " company in the "
    . $stock{symbol}{industry} . " sector, with $oshares outstanding shares of class-A stock.";
}

sub newstock {
  my @letter  = qw(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z);
  my $ind       = $industry[rand @industry];
  my $stockname = newcompanyname($ind);
  my $symbol    = abbreviate_stockname($stockname);
  my $slength   = (30 > rand 100) ? 4 : 3;
  my $tries     = 0;
  while (((not $symbol) or (ref $stock{$symbol})) and ($tries++ < 5)) {
    # If the symbol doesn't match the company name, it's not a big deal.  Real-world stock ticker
    # symbols are frequently based on an old name that is no longer used, or are chosen arbitrarily
    # when the symbol that was wanted was already taken.  The important thing is that it's unique.
    $symbol = join "", map { $letter[rand @letter] } 1 .. $slength;
  }
  return if not $symbol;
  return if ref $stock{$symbol};
  my $price = sprintf("%0.2f", rand 100);
  for (1 .. 4) {
    if (30 > rand 100) {
      $price = $price * ((50 > rand 100) ? 5 : 2);
    }
    if (30 > rand 100) {
      $price = $price / ((50 > rand 100) ? 5 : 2);
    }}
  $price = (int($price * 1000) || 1) / 10;
  while ($price < 100) {
    $price = 2 * $price;
  }
  my $sales = int rand 50000;
  for (1 .. 10) {
    if (50 > rand 100) {
      $sales = $sales * 10;
    }}
  my $assets = $sales;
  for (1 .. 4) {
    if (50 > rand 100) {
      $assets = $assets * 10;
    } else {
      $assets = $assets / 10;
    }}
  my $ccash = $sales;
  for (1 .. 6) {
    if (30 > rand 100) {
      $ccash = $ccash * ((70 > rand 100) ? 2 : 5);
    } else {
      $ccash = $ccash / 10;
    }}
  $ccash = 1000 + int $ccash;
  my $sdebt = $assets;
  for (1 .. 5) {
    if (50 > rand 100) {
      $sdebt = $sdebt * 2;
    } else {
      $sdebt = $sdebt / 2;
    }}
  $sdebt = int $sdebt; $sdebt = 0 if $sdebt < 1000;
  return +{ symbol   => $symbol,
            name     => $stockname,
            industry => $$ind{industry},
            owned    => 0,
            shares   => 1000000 * int(5 + ((1 + rand 2) * (1 + rand 2) * (1 + rand 5) * (1 + rand 5))),
            price    => $price,
            sales    => $sales,
            assets   => $assets,
            cash     => $ccash,
            debt     => $sdebt,
            idx      => int rand 65535, # for ticker-order continuity across save/restore.
            movement => 0,
          };
}

sub newcompanyname {
  my ($i) = @_;
  # TODO: sometimes use standard corporate affixes like "Global", ", Inc.", "LLC", etc.
  my $suffix = (("CODE" eq ref $$i{suffix})
                ? ($$i{suffix}->())
                : ((95 > rand 100)
                   ? (" " . ucfirst randomsyllable())
                   : ucfirst randomsyllable()));
  my $prefix = ((ref $$i{prefix})
                ? $$i{prefix}->()
                : (ucfirst(randomsyllable()) . ((85 > rand 100) ? " " : "")));
  my @nameword = (@commonsurname,
                  map { join "", map { randomsyllable() } 1 .. 2 + int rand 2 } 1 .. 25,
                 );
  my $basename;
  if (50 > rand 100) {
    my $word = $nameword[int rand @nameword];
    if (not $word =~ /[szcx][hz]?$/) {
      my @suff = ((("s") x 10),
                  (("'s") x 5),
                  "s'", "z", "Z");
      $word .= $suff[rand @suff];
    } elsif (($word =~ /s$/) and (25 > rand 100)) {
      $word .= "on";
    }
    $basename = ucfirst $word;
  } elsif (10 > rand 100) {
    # Note: this ignores the prefix and suffix, because stringing three together is already long.
    # Thus it should not be very common, hence the low probability.
    return ucfirst($nameword[int rand @nameword]) . ", "
      . ucfirst($nameword[int rand @nameword]) . ", "
      . ((80 > rand 100) ? "and" : "&") . " "
      . ucfirst($nameword[int rand @nameword]);
  } else {
    my $one = $nameword[int rand @nameword];
    my $two = $nameword[int rand @nameword];
    my @joiner = (((" & ", " and ", "-") x 5),
                  ((" ") x 12),
                  "/", "");
    $basename = ucfirst($one) . $joiner[int rand @joiner] . ucfirst($two);
  }
  return $prefix . $basename . $suffix;
}

sub stock_market_industries {
  return (+{ industry   => "Agribusiness",
             volatility => 50,
             growth     => 5,
             
           },
          +{ industry   => "Financial",
             volatility => 70,
             growth     => 60,
           },
          +{ industry   => "Transportation",
             volatility => 20,
             growth     => 20,
           },
          +{ industry   => "Retail",
             volatility => 45,
             growth     => 35,
           },
          +{ industry   => "Medical",
             volatility => 50,
             growth     => 60,
           },
          +{ industry   => "Tourism",
             volatility => 60,
             growth     => 50,
           },
          +{ industry   => "Entertainment",
             volatility => 90,
             growth     => 35,
           },
          +{ industry   => "Hamartics",
             volatility => 30,
             growth     => 30,
           }
          +{ industry   => "Technology",
             volatility => 30,
             growth     => 80,
             suffix     => sub { my @letter  = qw(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z);
                                 if (20 > rand 100) {
                                   my @s = (" Tech", "tech", " Technology");
                                   return $s[rand @s];
                                 } elsif (30 > rand 100) {
                                   return "";
                                 } elsif (40 > rand 100) {
                                   return " " . uc join "", map { $letter [@letter] } 1 .. ((80 > rand 100) ? 2 : 3);
                                 }
                                 my @s = (" Systems", " Technology", " Software", " Microsystems", " Data",
                                          " Computing", " Computer",  " Infosystems", " Infotech", " Automation",
                                          " Robotics", " Digital", " Digitech", " Solutions",
                                          "sys", "ware", "icity", "ity", "comp", "mation", "etics", "ata");
                                 if (40 > rand 100) {
                                   push @s, $_ for (" Chips", " Circuits", " Social", " Media", " IT",
                                                    " Machines", " Boards", " Power", " Cloud", " Energy",
                                                    " Mobile", " Communications",
                                                   );
                                 }
                                 if (20 > rand 100) {
                                   push @s, $_ for (" Integrated", " Cryptography", " Analysis", " Cybernetics",
                                                    " Fabrication", " Meta", " Mega", " Alpha", " Beta");
                                 }
                                 return $s[rand @s];
                               },
           },
          );
}

#################################################################################################
#################################################################################################
###
###                                 W I N D O W    I T E M S :
###
#################################################################################################
#################################################################################################

sub windowitems {
  my ($w) = @_;
  my @item;
  # my $wi = ($$w{helpmode} and $$w{helpinfo})
  #  ? $$w{helpinfo}
  #  : $windowitem{$$w{subtype}};
  my $wi = $windowitem{$$w{subtype}};
  if ('CODE' eq ref $wi) {
    @item = $wi->($w);
  } elsif ('ARRAY' eq ref $wi) {
    @item = @{$wi};
  }
  debuglog("windowitems() returning " . @item . " items for " . $$w{title});
  return @item;
}

sub settings_items {
  if ($setting) {
    my ($o) = grep { $$_{name} eq $setting } @option;
    # TODO: maybe support option types
    #       other than enum?
    return @{$$o{enum}};
  } else {
    return ( (map {
      my $o = $_;
      +{ key   => $$o{key},
         name  => $$o{name},
         value => $option{$$o{name}},
       },
     } grep {
       $$_{key},
     } @option),
             +{ key => "S",
                name => "Save",
                value => "" },
           );
  }
}

sub budget_items {
  if ($budgetitem) {
    # TODO: support things other than enum, maybe at some point
    return map {
      my $e = $_;
      +{ name  => $$e{name},
         key   => $$e{key},
         value => $budget{$budgetitem}{budget}->($$e{name}),
       },
    } @{$budget{$budgetitem}{enum}}
  } else {
    return map {
      +{ key   => $budget{$_}{key},
         name  => $budget{$_}{name},
         value => $budget{$_}{value},
       },
    } sort {
      ($budget{$a}{sort} || $budget{$a}{value}) <=> ($budget{$b}{sort} || $budget{$b}{value})
    } grep {
      (not $budget{$_}{unlock}) or
        ($budget{$_}{unlock} < ($cashflow{total}{sales} || 0))
    } keys %budget;
  }
}

sub init_windowitems {
  return   (
   cashflow => sub {
     my ($w) = @_;
     my $prefix = "";
     debuglog(qq[init_windowitems: cashflow mode is "$$w{mode}".]);
     my @cfitem = (["Sales", "sales", undef],
                   ["Budget", "budget", undef],
                   ["Essentials", "essentials", undef],
                   ["Investment", "investment", undef], # includes land, licenses, interest, stocks, bonds
                   ["Purchases", "purchases", undef],
                  );
     if ($$w{mode}) {
       $prefix = ucfirst($$w{mode}) . " ";
       @cfitem = map {
         [ucfirst($_), $$w{mode}, $_],
       } sort {
         $cashflow{sc}{total}{$$w{mode}}{$a} <=> $cashflow{sc}{total}{$$w{mode}}{$b}
       } keys %{$cashflow{sc}{total}{$$w{mode}}};
     }
     return ( map {
       my ($seclabel, $flowkey) = @$_;
       ( +{ name  => $prefix . $seclabel,
            fg    => "white",
          },
         (map {
           my ($name, $catkey, $subcat) = @$_;
           my @clrinfo = (); @clrinfo = ( fg => "green" ) if $catkey eq "sales";
           my $value = $$w{mode}
             ? ($cashflow{sc}{$flowkey}{$catkey}{$subcat} || 0)
             : ($cashflow{$flowkey}{$catkey} || 0);
           +{ name  => $name,
              value => shownum($value),
              @clrinfo,
            },
         } @cfitem),
         +{ name  => "", },
       )
     } (["This Month", "current"],
        ["Last Month", "lastmonth"],
        ["Last Year",  "lastyear"],
        ["Total",      "total"]));
   },
   buy => sub {
     my $k = "a";
     if ($buystock) {
       my ($industry) = grep { $$_{industry} eq $buystock } @industry;
       if ($industry) {
         my @sym = grep { $stock{$_}{industry} eq $industry } keys %stock;
         return (
                 (map {
                   my $s = $_;
                   my $key = $k++;
                   if ($key eq "c") {
                     $key = $k++;
                   }
                   +{ name    => $s . "=" . $stock{$s}{name},
                      key     => $key,
                      cost    => shownum($stock{$s}{price}),
                      fg      => $$industry{fg} || "blue",
                      hilight => $$industry{hilightfg} || "cyan",
                    },
                  } @sym),
                 +{ name    => "cancel",
                    key     => "c",
                    cost    => "0",
                    fg      => $$industry{fg} || "blue",
                    hilight => $$industry{hilightfg} || "cyan",
                  },
                );
       } elsif ($stock{$buystock}) {
         my $avail = $stock{$buystock}{shares} - $stock{$buystock}{owned};
         my @qtty  = grep { $buyqtty{$_}{number} le $avail } @bytens;
         return ((map { my $q = $buyqtty{$_};
                        my $price = $stock{$buystock}{price} * $$q{number};
                        +{ key     => $$q{key},
                           name    => $$q{name},
                           number  => $$q{number},
                           value   => shownum($price),
                           cost    => $price,
                           fg      => $$q{fg} || (($price <= $cash) ? "blue" : "grey"),
                           hilight => $$q{hilight} || (($price <= $cash) ? "cyan" : "black"),
                         },
                      } @qtty),
                 +{ name    => "cancel",
                    key     => "c",
                    cost    => "0",
                    fg      => $$industry{fg} || "blue",
                    hilight => $$industry{hilightfg} || "cyan",
                  },
                 (map {
                   +{ name => $_,
                      fg   => $$wbuy{helpcolor} || $$wbuy{fg} || "grey",
                    },
                  } format_help_info($wbuy, describestock($buystock))));
       } elsif ($buystock eq "category") {
         return (
                 (map {
                   my $i = $_;
                   my $key = $k++;
                   if ($key eq "c") {
                     $key = $k++;
                   }
                   +{ name    => ucfirst $$i{industry},
                      key     => $key,
                      cost    => "?",
                      fg      => $$i{fg} || "blue",
                      hilight => $$i{hilightfg} || "cyan",
                    },
                  } @industry),
                 +{ name    => "cancel",
                    key     => "c",
                    cost    => "0",
                    fg      => $$wbuy{fg} || "blue",
                    hilight => $$wbuy{hilightfg} || "cyan",
                  },
                );
       #} elsif () {
       }
     } elsif ($buyitem) {
       return (+{ name => ucfirst $asset{$buyitem}{name},# . " <" . $asset{$buyitem}{id} . ">",
                  fg   => "teal",
                },
               #(+{ name => join("", "[", (keys %{ $asset{$buyitem}{unlocked}{buy}}), "]"),
               #    fg   => "orange",
               #  }),
               map {
                 my $qid = $_;
                 my $q = $buyqtty{$qid};
                 my $price = $$q{price} || $asset{$buyitem}{value} * $$q{pmult};
                 +{ key     => $$q{key},
                    name    => $$q{name},# . " <" . $$q{id} . ">",
                    number  => $$q{number},
                    value   => (($$q{number} eq "asneeded")
                                ? ($asset{$buyitem}{asneeded} ? "(on)" : shownum($price))
                                : shownum($price)),
                    cost    => $price,
                    fg      => $$q{fg} || (($price <= $cash) ? "blue" : "grey"),
                    hilight => $$q{hilight} || (($price <= $cash) ? "cyan" : "black"),
                  },
                } grep {
                  $_ and
                  (($_ eq "cancel") or $asset{$buyitem}{unlocked}{buy}{$_})
                } @{$asset{$buyitem}{buyqtty} || [qw(1 12 144)]}, "cancel"),
                (map {
                  +{ name => $_,
                     fg   => $$wbuy{helpcolor} || $$wbuy{fg},
                   },
                 } format_help_info($wbuy, $asset{$buyitem}{desc}));
     }
     return map {
       my $id = $_;
       +{ id      => $id,
          key     => $k++,
          name    => $asset{$id}{name},
          value   => shownum($asset{$id}{value}),
          fg      => ($asset{$id}{value} <= $cash) ? ($asset{$id}{assetfg} || "green") : "grey",
          hilight => ($asset{$id}{value} <= $cash) ? "yellow" : "black",
        },
     } sort {
       ($asset{$a}{sort} || $asset{$a}{value}) <=> ($asset{$b}{sort} || $asset{$b}{value})
     } grep {
       my $atype = $_;
       $asset{$atype}{good} and
       (grep { $asset{$atype}{unlocked}{buy}{$_} } keys %{$asset{$atype}{unlocked}{buy} || +{}})
     } keys %asset;
   },
   assets   => sub {
     # TODO: allow colors to be customized
     my @investmentitem;
     push @investmentitem, +{ name  => "Bonds",
                              value => (scalar @bond),
                              fg    => "gold" }
       if scalar @bond;
     push @investmentitem, +{ name => "Loans(t)",
                              value => shownum($debt),
                              fg    => "red" }
       if $debt;
     # TODO: stonks.
     return (
             +{ name  => "Cash",
                value => shownum($cash),
                fg    => "gold" },
             @investmentitem,
             (map {
                +{ name  => ucfirst($asset{$_}{plural} || makeplural($asset{$_}{name})),
                   value => shownum($asset{$_}{qtty}),
                   fg    => $asset{$_}{assetfg},
                 },
              } sort {
                $asset{$a}{sort} <=> $asset{$b}{sort}
              } grep {
                $asset{$_}{good} and ($asset{$_}{qtty} >= 1)
              } keys %asset),
            );
   },
   budget   => [budget_items()],
   settings => [settings_items()],
  );
}

#################################################################################################
#################################################################################################
###
###                                          I N P U T:
###
#################################################################################################
#################################################################################################

sub process_key {
  my ($k) = @_;
  debuglog("Processing key '$k' (ordinal value " . ord($k) . ").");
  if ((exists $globalkeybinding{$inputprefix . $k}) and
      (ref $globalkeybinding{$inputprefix . $k}) and
      ('CODE' eq ref $globalkeybinding{$inputprefix . $k})) {
    $globalkeybinding{$inputprefix . $k}->($k);
    $inputprefix = "";
  } elsif ((exists $globalkeybinding{$inputprefix . $k}) and
           ("prefix" eq $globalkeybinding{$inputprefix . $k})) {
    $inputprefix .= $k;
  } elsif ($wfocus and ref $$wfocus{input}) {
    my $result = $$wfocus{input}->($wfocus, $inputprefix . $k);
    $inputprefix = "";
    eggwidget_onscroll($wfocus);
    return $result;
  } else {
    debuglog("Nothing to do with keystroke '$k'.");
  }
}

sub global_key_bindings {
  return (
          chr(27) . chr(91) => "prefix",
          chr(27) . chr(91) . chr(65) => sub { # up arrow
            scroll_widget_to($wfocus, ($$wfocus{vscrollpos} || 0) - 1);
          },
          chr(27) . chr(91) . chr(66) => sub { # down arrow
            scroll_widget_to($wfocus, ($$wfocus{vscrollpos} || 0) + 1);
          },
          chr(27) . chr(91) . chr(53) => "prefix",
          chr(27) . chr(91) . chr(53) . chr(27) => "prefix",
          chr(27) . chr(91) . chr(53) . chr(27) . chr(91) => "prefix",
          chr(27) . chr(91) . chr(53) . chr(126) => sub { # PgUp
            scroll_widget_to($wfocus, ($$wfocus{vscrollpos} || 0) - ($$wfocus{contentsizey} || 1));
          },
          chr(27) . chr(91) . chr(53) . chr(27) . chr(91) . chr(126) => sub { # PgUp
            scroll_widget_to($wfocus, ($$wfocus{vscrollpos} || 0) - ($$wfocus{contentsizey} || 1));
          },
          chr(27) . chr(91) . chr(54) => "prefix",
          chr(27) . chr(91) . chr(54) . chr(126) => sub { # PgDn
            scroll_widget_to($wfocus, ($$wfocus{vscrollpos} || 0) + ($$wfocus{contentsizey} || 1));
          },
          chr(27) . chr(91) . chr(54) . chr(27) => "prefix",
          chr(27) . chr(91) . chr(54) . chr(27) . chr(91) => "prefix",
          chr(27) . chr(91) . chr(54) . chr(27) . chr(91) . chr(126) => sub { # PgDn
            scroll_widget_to($wfocus, ($$wfocus{vscrollpos} || 0) + ($$wfocus{contentsizey} || 1));
          },
          chr(27) . chr(91) . chr(70) => sub { # End
            scroll_widget_to($wfocus, ($$wfocus{vscrollend} || 0));
          },
          chr(27) . chr(91) . chr(72) => sub { # Home
            scroll_widget_to($wfocus, ($$wfocus{vscrollhome} || 0));
          },
          chr(9) => sub { # Tab:
            rotate_focus(1); # TODO: test this; I'm not sure it's working.
          },
          # TODO: shift-tab should go the other way.
          chr(16) => sub { # Ctrl-P:
            toggle_pause();
          },
          chr(18) => sub { # Ctrl-R:
            redraw(@_);
          },
          chr(24) => sub { # Ctrl-X
            # TODO: automatically save unless the user has set an option to NOT do that.
            print "\nExiting game at user request.\n"; exit 0;
          },
          "?" => sub {
            dohelp($wfocus);
          },
          chr(27) => "prefix", # Esc
          chr(27) . chr(79) => "prefix", # Esc O, prefix for function keys F1 - F4
          chr(27) . chr(79) . chr(80) => sub { # F1 = Help
            dohelp($wfocus);
          },
          chr(27) . chr(79) . chr(81) => sub {
            # F2 = [reserved for future use]
          },
          chr(27) . chr(79) . chr(82) => sub { # F3 = Buy
            setfocus($wbuy);
          },
          chr(27) . chr(79) . chr(83) => sub { # F4 = Save
            savegame();
          },
          chr(27) . chr(91) => "prefix", # Esc [
          chr(27) . chr(91) . chr(49) => "prefix", # Esc [1
          chr(27) . chr(91) . chr(49) . chr(53) => "prefix", # Esc [15
          chr(27) . chr(91) . chr(49) . chr(53) . chr(126) => sub { # F5 = Redraw
            redraw(@_);
          },
          chr(27) . chr(91) . chr(49) . chr(55) => "prefix", # Esc [17
          chr(27) . chr(91) . chr(49) . chr(55) . chr(126) => sub { # F6 = Budget
            setfocus($wbudget);
          },
          chr(27) . chr(91) . chr(49) . chr(56) => "prefix", # Esc [18
          chr(27) . chr(91) . chr(49) . chr(56) . chr(126) => sub { # F7 Assets
            setfocus($wassets);
          },
          chr(27) . chr(91) . chr(49) . chr(57) => "prefix", # Esc [19
          chr(27) . chr(91) . chr(49) . chr(57) . chr(126) => sub { # F8 = Messages
            setfocus($wmessages);
          },
          chr(27) . chr(91) . chr(50) => "prefix", # Esc [2
          chr(27) . chr(91) . chr(50) . chr(48) => "prefix", # Esc [20
          chr(27) . chr(91) . chr(50) . chr(48) . chr(126) => sub { # F9 = Cash Flow
            setfocus($wcashflow);
          },
          chr(27) . chr(91) . chr(50) . chr(49) => "prefix", # Esc [21
          chr(27) . chr(91) . chr(50) . chr(49) . chr(126) => sub { # F10 = Settings
            setfocus($wsettings);
          },
          # F11 is intercepted by Konsole, probably other terminals as well, for full-screen.
          chr(27) . chr(91) . chr(50) . chr(52) => "prefix", # Esc [24
          chr(27) . chr(91) . chr(50) . chr(52) . chr(126) => sub { # F12 = Debug
            setfocus($wordkey) if $wordkey;
          },

         );
}

sub dohelp {
  my ($w) = @_;
  my @m;
  if (ref $$w{helpinfo}) {
    if ("ARRAY" eq ref $$w{helpinfo}) {
      @m = @{$$w{helpinfo}};
    } elsif ("CODE" eq ref $$w{helpinfo}) {
      @m = $$w{helpinfo}->();
    } else {
      @m = ("Error: malformed help info for $$w{title}");
    }
  }
  else {
    @m = globalhelp();
    push @m, qq[No widget-specific help info for $$w{title}, sorry.];
  }
  for my $msg (@m) {
    push @message, [$msg, "help"];
  }
}

sub globalhelp {
  return (qq[Press F1 for help, F4 to save, F5 to redraw the screen.  Other function keys select the various widgets, as labeled.]);
}

sub input_messagelog {
  my ($w, $k) = @_;
  #if ($k eq ) {
  #}
}

sub input_cashflow {
  my ($w, $k) = @_;
  $$w{helpmode} = undef;
  if ($k eq "s") {
    $$w{mode} = "sales";
  } elsif ($k eq "b") {
    $$w{mode} = "budget";
  } elsif ($k eq "p") {
    $$w{mode} = "purchases";
  } elsif ($k eq "e") {
    $$w{mode} = "essentials";
  } elsif ($k eq "i") {
    $$w{mode} = "investment";
  } else {
    $$w{mode} = "";
  }
  debuglog("Set cashflow widget mode to $$w{mode}.");
}
sub input_budget {
  my ($w, $k) = @_;
  if ($budgetitem) {
    my ($e) = grep {
      $$_{key} eq $k
    } @{$budget{$budgetitem}{enum}};
    $budget{$budgetitem}{value} = $$e{name};
    $budgetitem = undef;
  } else {
    ($budgetitem) = grep {
      $budget{$_}{key} eq $k
    } keys %budget;
  }
  $windowitem{budget} = [budget_items()];
}

sub input_stockmarket {
  croak "TODO";
}

sub input_buy {
  my ($w, $k) = @_;
  my @item = windowitems($w);
  if ($buystock) {
    return input_stockmarket($w, $k);
  } elsif ($buyitem) {
    my ($i) = grep { $k eq $$_{key} } @item;
    if ($$i{placetype}) {
      croak "TODO";
    } elsif (($$i{number} > 0) and ($$i{value} <= $cash)) {
      if (safetobuy($buyitem, $$i{number})) {
        buyasset($buyitem, $$i{number}, $$i{cost}, "player");
      } else {
        my $roomword = "don't have room for";
        my $hereword = "";
        if ($asset{$buyitem}{chicken}) {
          $asset{$asset{$buyitem}{housein}}{unlocked}{buy}{1} ||= 1;
        } elsif ($asset{$buyitem}{landsize}) {
          $asset{acre}{unlocked}{1} ||= 1;
        } elsif ($asset{$buyitem}{licenseneeded}) {
          $asset{license}{unlocked}{$asset{$buyitem}{licenseneeded}} ||= 1;
          $roomword = "can't find";
          $hereword = " for sale here";
        }
        push @message, ["You $roomword " . shownum($$i{number}) . " more " .
                        sgorpl($$i{number}, $asset{$buyitem}{name},
                               $asset{$buyitem}{plural}) . $hereword . ".", "actioncancel"];
      }
    } elsif ($$i{number} eq "cancel") { # Cancel buy-as-needed
      $asset{$buyitem}{asneeded} = undef;
    } elsif ($$i{number} eq "asneeded") { # Start buy-as-needed
      if ($asset{$buyitem}{unlocked}{buy}{asneeded}) {
        $asset{$buyitem}{asneeded} = 1;
      } else {
        debuglog("As-needed not unlocked for $buyitem.");
        push @message, ["Error: buy as needed activated when not unlocked.", "bug"];
      }
    }
    $buyitem = undef;
  } else {
    my ($i) = grep { $k eq $$_{key} } @item;
    $buyitem = $i ? $$i{id} : undef;
    $debughint = $buyitem;
  }
}

sub input_settings {
  my ($w, $k) = @_;
  my @item = windowitems($w);
  if ($k eq "S") { # This is the hardcoded key for saving the options.
    saveoptions();
  } elsif ($setting) {
    my ($o) = grep { $$_{name} eq $setting } @option;
    # TODO: maybe suport option types other than enum/multiple-choice ?
    my ($i) = grep { $$_{key} eq $k } @item;
    if ($i) {
      $option{$$o{name}} = $$i{value};
      changed_color_depth() if $setting eq "colordepth";
      $setting = undef;
      $windowitem{settings} = [settings_items()];
    }
  } else {
    my ($i) = grep { $k eq $$_{key} } @item;
    if ($i) {
      $setting = $$i{name};
      $windowitem{settings} = [settings_items()];
    }
  }
}

#################################################################################################
#################################################################################################
###
###                                        W I D G E T S :
###
#################################################################################################
#################################################################################################

sub drawwidgets {
  for my $w (@widget) {
    redraw_widget($w, $screen);
  }
}

sub scroll_eggwidget_to_end {
  my ($w) = @_;
  my (@wi) = windowitems($w);
  return ((scalar @wi) + 1 - $$w{contentsizey});
}

sub eggwidget_onscroll {
  my ($w) = @_;
  my (@wi) = windowitems($w);
  if ($$w{vscrollpos} > ((1 + scalar @wi) - $$w{contentsizey})) {
    $$w{vscrollpos} = (1 + scalar @wi) - $$w{contentsizey};
  } elsif ($$w{vscrollpos} < 0) {
    $$w{vscrollpos} = 0;
  }
}

sub doeggwidget {
  my ($w, $s, @more) = @_;
  $$w{bg} ||= "black";
  my %moropt = @more;
  my $hbg = $option{focusbgcolor} || $$w{focusbg} || "black";
  my $bg  = (($$w{id} eq $$wfocus{id}) ? $hbg : undef) ||
    ($$w{transparent} ? '__TRANSPARENT__' : $$w{bg}) ||
    '__TRANSPARENT__';
  debuglog("Drawing widget $$w{id} ($$w{type}/$$w{subtype}), fg=$$w{fg}/$$w{focusbg}, bg=$$w{bg}, xp=$$w{transparent}, on a $bg background.");
  debuglog("Geometry: ($$w{x},$$w{y}) / ($$w{xmax},$$w{ymax})");
  if ($$w{redraw} or ($bg and ($bg ne "__TRANSPARENT__"))) {
    blankrect($s, $$w{x}, $$w{y}, $$w{xmax}, $$w{ymax},
              sub { my ($x,$y) = @_;
                    my $stbg = $option{$$w{subtype} . "bg"};
                    colorlog("sub [that doeggwidget passed to blankrect]: asking widgetbg for '$stbg', passing old=" . Dumper($$s[$x][$y]));
                    return widgetbg($w, $stbg, $$s[$x][$y]);
                  }, " ", widgetfg($w));
    doborder($w, $s, @more);
  }
  my $n = 0;
  my @wi = windowitems($w);
  $$w{vscrollend} = sub { scroll_eggwidget_to_end($w) };
  if ($$w{vscrollpos} > 1) {
    # TODO: handle re-using keys when scrolling through so many items that there aren't enough keys.
    #       I want this capability for the stock market.
    for (1 .. ($$w{vscrollpos} - 1)) {
      shift @wi;
    }}
  for my $i (@wi) {
    $n++;
    if ($$w{y} + $n + 1 < $$w{ymax}) { # TODO: allow scrolling if needed.
      if ($$i{key}) {
        dotext(+{ id          => $$w{id} . "_keylabel_" . $n,
                  text        => $$i{key},
                  x           => $$w{x} + 1,
                  y           => $$w{y} + $n,
                  bg          => $bg,
                  fg          => $$i{hilight} || $$i{fg} || $$w{hilight} || $$w{fg},
                  transparent => $$w{transparent},
                }, $s);
      }
      debuglog(qq[window $$w{id}, item $n, $$i{name} at (]
               . ($$w{x} + 1 + ($$i{key} ? 2 : 0))
               . ","
               . ($$w{y} + $n)
               . qq[), ] . ($$i{fg} || $$w{fg}) . " on $bg" . ($$w{transparent} ? ", xparent" : ""));
      dotext(+{ id          => $$w{id} . "_label_" . $n,
                text        => substr($$i{name}, 0, $$w{xmax} -$$w{x} - 2),
                x           => $$w{x} + 1 + ($$i{key} ? 2 : 0),
                y           => $$w{y} + $n,
                bg          => $bg,
                fg          => $$i{fg} || $$w{fg},
                transparent => $$w{transparent},
              }, $s);
      # The value, if present, will write overtop, effectively
      # truncating the label if necessary.  We prefix it with a space
      # to ensure they don't run together.
      dotext(+{ id          => $$w{id} . "_value_" . $n,
                text        => " " . substr($$i{value}, 0, $$w{xmax} - $$w{x} - 3),
                x           => $$w{xmax} - length($$i{value}) - 2,
                y           => $$w{y} + $n,
                bg          => $bg,
                fg          => $$i{fg} || $$w{fg},
                transparent => $$w{transparent},
              }, $s)
        if defined $$i{value};
    }}
}

sub doticker {
  my ($w, $s, @more) = @_;
  return if $$w{disabled};
  # For now, for debugging, I want it to show all the time.
  #return if $gamephase < 3;
  my @sym = @{$$w{list} || +[]};
  if ((not scalar @sym) or not ($$w{rotate_counter} % 3)) {
    my %onlist = map { $_ => 1 } @sym;
    my @add = sort {
      $stock{$b}{idx} <=> $stock{$a}{idx}
    } grep {
      not $onlist{$_}
    } keys %stock;
    push @add, shift @sym;
    @sym = (@sym, @add);
    $$w{list} = [@sym];
  }
  $$w{rotate_counter}++;
  my $length = 1;
  my $hbg = $option{focusbgcolor} || $$w{focusbg} || $$w{bg} || "black";
  my $bg  = (($$w{id} eq $$wfocus{id}) ? $hbg : undef) ||
    ($$w{transparent} ? '__TRANSPARENT__' : $$w{bg}) ||
    '__TRANSPARENT__';
  if ($$w{redraw} or ($bg and ($bg ne "__TRANSPARENT__")) or (not ($$w{rotate_counter} % 3))) {
    blankrect($s, $$w{x}, $$w{y}, $$w{xmax}, $$w{ymax},
              sub { my ($x,$y) = @_;
                    colorlog("sub [that doeggwidget passed to blankrect]: asking widgetbg for 'tickerbg', passing old=" . Dumper($$s[$x][$y]));
                    return widgetbg($w, "tickerbg", $$s[$x][$y]);
                  }, " ", widgetfg($w));
    my $posn = 1;
    while ((($posn + 9) < $xmax) and (scalar @sym)) {
      my $symbol = shift @sym;
      if ($symbol) {
        my $length = length($symbol) + 1;
        my $price  = shownum($stock{$symbol}{price}) || "?";
        $length += length($price);
        my $movement = "";
        if ($stock{$symbol}{movement}) {
          $movement = ($stock{$symbol}{movement} > 0) ? "↑" : "↓";
          $length++;
        }
        if ($posn + $length + 1 < $xmax) {
          dotext(+{ id          => $$w{id} . "__stock__" . $symbol . "__symbol",
                    text        => $symbol,
                    x           => $posn,
                    y           => $$w{y},
                    bg          => $$w{bg},
                    fg          => $$w{fg} || "white",
                    transparent => $$w{transparent},
                  }, $s);
          dotext(+{ id          => $$w{id} . "__stock__" . $symbol . "__price",
                    text        => $price,
                    x           => $posn + length($symbol) + 1,
                    y           => $$w{y},
                    bg          => $$w{bg},
                    fg          => $$w{pricefg} || $$w{fg} || "yellow",
                    transparent => $$w{transparent},
                  }, $s);
          my $mvtcolor = ($stock{$symbol}{movement} > 0) ? ($$w{posmovementfg} || "green") : ($$w{negmovementfg} || "red");
          dotext(+{ id          => $$w{id} . "__stock__" . $symbol . "__movement",
                    text        => $movement,
                    x           => $posn + length($symbol) + 1 + length($price),
                    y           => $$w{y},
                    bg          => $$w{bg},
                    fg          => $mvtcolor,
                    transparent => $$w{transparent},
                  }, $s);
          $posn += $length + 1;
        }
      }
    }
  }
}

sub dowidget {
  my ($w, $s, @more) = @_;
  if (is_standard_widget($w)) {
    dostandardwidget($w, $s, @more);
  } elsif ($$w{type} eq "egggame") {
    doeggwidget($w, $s, @more);
  } elsif ($$w{type} eq "ticker") {
    doticker($w, $s, @more);
  } else {
    widgetlog("unhandled widget type, '$$w{type}'");
    dotext($w, $s, @more);
  }
}

#################################################################################################
#################################################################################################
###
###                                     S A V E  /  L O A D :
###
#################################################################################################
#################################################################################################

sub get_config_dir {
  my $homedir = $ENV{HOME} || File::HomeDir->my_home || cwd();
  # TODO: check for MS Windows and do AppData things here.
  my $path = catfile($homedir, ".config", "Eggs");
  return $path if -d $path;
  system("mkdir", "-p", $path);
  die "Path does not exist: $path" if not -e $path;
  die "Not a directory: $path" if not -d $path;
  return $path;
}

sub loadoptions {
  my ($o) = @_;
  my $fn = $$o{optionsfile} || catfile(get_config_dir(), "eggs.cfg");
  if (-e $fn) {
    open OPT, "<", $$o{optionsfile} or die "Cannot read options file $$o{optionsfile}: $!";
    debuglog("Reading options file ($$o{optionsfile}).");
    while (<OPT>) {
      my $line = $_;
      if ($line =~ /^Eggs v(.*) Options File$/) {
        my ($ver) = $1;
        if ($ver ne $version) {
          debuglog("Options file was written with version $ver, but we are reading it with version $version.");
        }
      } elsif ($line =~ /^\s*$/) {
        # Ignore blank line.
      } elsif ($line =~ /^\s*#/) {
        # Ignore comment line.
      } elsif ($line =~ /^\s*([^=]+)[=](.*?)\s*$/) {
        my ($key, $val) = ($1, $2);
        my ($opt) = grep { $$_{name} eq $key } @option;
        if (ref $opt) {
          if ($$opt{save} =~ /user/) {
            if (ref $$opt{enum}) {
              my ($e) = grep { $$_{value} eq $val } @{$$opt{enum}};
              if (ref $e) {
                $$o{$key} = $$e{value};
              } else {
                debuglog("Options file specified unknown value for option: '$key' = '$val'");
              }
            } elsif (ref $$opt{regex}) {
              my ($washed) = ($val =~ $$opt{regex});
              if ($washed and ($washed eq $val)) {
                $$o{$key} = $washed;
              } else {
                debuglog("Options file specified irregular value for option: '$key' = '$val'")
              }
            } else {
              debuglog("Don't know how to validate value for option: '$key' = '$val'");
            }
          } else {
            debuglog("Options file contains an option it should not: '$key' = '$val'");
          }
        } else {
          debuglog("Options file contains spurious option: '$key' = '$val'");
        }
      }
    }
    close OPT;
    return $o;
  } else {
    debuglog("Options file does not exist: $fn");
    return;
  }
}

sub saveoptions {
  my $fn = $option{optionsfile} || catfile(get_config_dir(), "eggs.cfg");
  open OPT, ">", $fn or die "Cannot write options file '$fn': $!";
  print OPT "Eggs v" . $version . " Options File\n";
  for my $o (grep { $$_{save} =~ /user/ } @option) {
    print OPT "\n";
    print OPT qq[# $$o{desc}\n];
    print OPT qq[# default: $$o{default}\n];
    print OPT qq[$$o{name}=$option{$$o{name}}\n];
  }
  print OPT qq[\n\n## EOF\n\n];
  close OPT;
  push @message, ["Options saved.", "meta"];
}

sub restoregame {
  my ($fn) = @_;
  $fn ||= $option{savefile} || catfile(get_config_dir(), "eggs.save");
  debuglog("Restoring $fn");
  if (open SAV, "<", $fn) {
    my %restored;
    while (<SAV>) {
      my $line = $_;
      if ($line =~ /^\s*Global[:](Date|RunStarted|NGPETA|BirthDate)=(\d+)-(\d+)-(\d+)/) {
        my ($whichdate, $y, $m, $d) = ($1, $2, $3, $4);
        my ($dt); eval {
          $dt = DateTime->new( year  => $y,
                               month => $m,
                               day   => $d,
                               hour  => 6,
                               time_zone => ($option{localtimezone} || "UTC"),
                             ); }; croak "DateTime error in restoregame()" if not ref $dt;
        if ($whichdate eq "Date") {
          $date = $dt;
        } elsif ($whichdate eq "RunStarted") {
          $runstarted = $dt;
        } elsif ($whichdate eq "NGPETA") {
          $ngpeta = $dt;
        } elsif ($whichdate eq "BirthDate") {
          $birthdate = $dt;
        } else {
          die "Unknown date variable: '$whichdate'.";
        }
        $restored{global}++;
      } elsif ($line =~ /^\s*Global[:]Cash=(\d+) zorkmid/) {
        $cash = $1;
        $restored{global}++;
      } elsif ($line =~ /^\s*Global[:]Debt=(\d+) trillion zm at (\d+)/) {
        ($debt, $creditrating) = ($1, $2);
      } elsif ($line =~ /^\s*Global[:]Primerate=([0-9.]+)%\s*$/) {
        $primerate = $1;
        $restored{global}++;
      } elsif ($line =~ /^\s*Global[:]Lvl=(.*?)\w*$/) {
        ($breedlvl, $genlvl, $genleak, $gamephase) = split /,/, $1;
        $restored{global}++;
      } elsif ($line =~ /^\s*Mode[:](\w+)=(.*?)\s*$/) {
        my ($wst, $mode) = ($1, $2);
        my ($w) = grep { $$_{subtype} eq $wst } @widget;
        if (ref $w) {
          $$w{mode} = $mode;
        } else {
          debuglog("Widget not found: $wst");
        }
      } elsif ($line =~ /^\s*Asset[:](\w+)=(\d*);([^;]*);([^;]*);(.*)/) {
        my ($atype, $num, $an, $unl, $trk) = ($1, $2, $3, $4, $5);
        $asset{$atype}{qtty} = $num;
        $asset{$atype}{asneeded} = ($an =~ /buy/) ? "buy" : undef;
        $restored{asset}++;
        if ($unl =~ /unlocked.buy=(.*)/) {
          my $list = $1;
          $asset{$atype}{unlocked}{buy} = +{ map { $_ => 1 } split /,\s*/, $list };
        }
        $asset{$atype}{agegroup} = +[
                                     map {
                                       my $t = $_;
                                       my ($q, $y, $m, $e, $s) = split /,\s*/, $t;
                                       $restored{agegroup}++;
                                       +{ qtty => $q, year => $y, month => $m,
                                          expire => $e, since => $s,
                                        };
                                     } grep { $_ } split /;\s*/, $trk
                                    ];
      } elsif ($line =~ /^\s*Budget[:](\w+)[:](.*?)\s*$/) {
        my ($bk, $val) = ($1, $2);
        $budget{$bk}{value} = $val;
        $restored{budget}++;
        #debuglog("Set budget for '$bk' to $budget{$bk}{value}")
      } elsif ($line =~ /^\s*Budgetted[:](\w+)[:](\d+)/) {
        my ($bk, $val) = ($1, $2);
        $budget{$bk}{progress} = $val;
        $restored{budget_progress}++;
      } elsif ($line =~ /^\s*CF[:](\w+)[:]([^:]+)/) {
        my ($timeframe, $rest) = ($1, $2);
        for my $pair (split /,\s*/, $rest) {
          my ($category, $number) = $pair =~ /([^=]+)[=](.*?)\s*$/;
          $cashflow{$timeframe}{$category} = $number;
          $restored{cashflow}++;
        }
      } elsif ($line =~ /^\s*CFSC[:](\w+)[:](\w+)[:](.*?)\s*$/) {
        my ($timeframe, $category, $rest) = ($1, $2, $3);
        for my $pair (split /,\s*/, $rest) {
          my ($subcat, $number) = $pair =~ /^([^=]+)=(.*)/;
          $cashflow{sc}{$timeframe}{$category}{$subcat} = $number;
          $restored{cfsubcat}++;
        }
      } elsif ($line =~ /^\s*Bond[:](.*?)\s*$/) {
        my ($rest) = ($1);
        #$rest =~ /(\w+),(\w+);(\d+);(\d+[-]\d+[-]\d+);(\d+[-]\d+[-]\d+);([0-9.]+)/;
        my ($id, $issuer, $amt, $issuedate, $maturedate, $rate) = split /;/, $rest;
        my %dt;
        for my $x (["issued", $issuedate],
                   ["mature", $maturedate]) {
          my ($dtname, $string) = @$x;
          if ($string =~ /(\d+)-(\d+)-(\d+)/) {
            my ($y, $m, $d) = ($1, $2, $3);
            eval { my $dt = DateTime->new( year      => $y,
                                           month     => $m,
                                           day       => $d,
                                           hour      => 12,
                                           time_zone => ($option{localtimezone} || "UTC"));
                   $dt{$dtname} = $dt;
                 };
            die "DateTime error parsing $dtname date from save file line: $line" if not ref $dt{$dtname};
          }}
        push @bond, +{ id     => $id,
                       issuer => $issuer,
                       amount => $amt,
                       issued => $dt{issued},
                       mature => $dt{mature},
                       rate   => $rate,
                     };
      } elsif ($line =~ /^\s*Stock[:](\w+)[=](.*?)\s*$/) {
        my ($symbol, $rest) = ($1,$2);
        my ($name, $industry, $sharecounts, $price, $sales, $assets, $cash, $sdebt, $index, $movement) = split /;/, $rest;
        die "Error parsing save-file line: $line" if not defined $sdebt;
        my ($owned, $totalshares) = split m(/), $sharecounts;
        $stock{$symbol} = +{ symbol   => $symbol,
                             name     => $name,
                             industry => $industry,
                             owned    => $owned,
                             shares   => $totalshares,
                             price    => $price,
                             sales    => $sales,
                             assets   => $assets,
                             cash     => $cash,
                             debt     => $sdebt,
                             idx      => $index,
                             movement => $movement,
                           };
      } elsif ($line =~ /^\s*Option[:]([^=]+)=(.*?)\s*$/) {
        my ($name, $value) = ($1, $2);
        $option{$name} = $value if defined $value;
        $restored{option}++;
      } elsif ($line =~ /^\s*Place[:](.*?)\s*$/) {
        my ($t, $n, $p) = split /;\s*/, $1;
        $p ||= undef; # Currently, worlds have no defined parent.
        push @extantplace, +{ type => $t, name => $n, parent => $p, };
      } elsif ($line =~ /^\s*County[:](.*?)\s*$/) {
        my ($name, $cap, $cword, $licensed, $size, $owned, $avail, $lcost, $parent) = split /;\s*/, $1;
        push @county, +{ name           => $name,
                         capital        => $cap,
                         capitalword    => $cword,
                         licensed       => $licensed,
                         size           => $size,
                         owned_land     => $owned,
                         available_land => $avail,
                         landcost       => $lcost,
                         parent         => $parent,
                       };
      } elsif ($line =~ /^\s*Province[:](.*?)\s*$/) {
        my ($name, $cap, $cword, $licensed, $size, $counties, $suffix, $parent) = split /;\s*/, $1;
        push @province, +{ name           => $name,
                           capital        => $cap,
                           capitalword    => $cword,
                           licensed       => $licensed,
                           size           => $size,
                           counties       => $counties,
                           countysuff     => $suffix,
                           parent         => $parent,
                         };
      } elsif ($line =~ /^\s*Nation[:](.*?)\s*$/) {
        my ($name, $cap, $cword, $licensed, $size, $provinces, $suffix, $parent) = split /;\s*/, $1;
        push @nation, +{ name           => $name,
                         capital        => $cap,
                         capitalword    => $cword,
                         licensed       => $licensed,
                         size           => $size,
                         provinces      => $provinces,
                         provincesuff   => $suffix,
                         parent         => $parent,
                       };
      } elsif ($line =~ /^\s*World[:](.*?)\s*$/) {
        my ($name, $cap, $cword, $licensed, $size, $nations, $parent) = split /;\s*/, $1;
        push @world, +{ name           => $name,
                        capital        => $cap,
                        capitalword    => $cword,
                        licensed       => $licensed,
                        size           => $size,
                        provinces      => $nations,
                        parent         => $parent,
                      };
        # TODO: larger jurisdictions
      } elsif ($line = /^\s*Message[:]([^:]+)[:](.*)/) {
        my ($channel, $text) = ($1, $2);
        push @message, [$text, $channel];
        $restored{message}++;
      } elsif ($line =~ /^\s*#/) {
        # Comment line, ignore it.
      } elsif ($line =~ /^\s*$/) {
        # Nothing but whitespace, ignore it.
      } else {
        die "restoregame(): failed to parse line: $line\n";
      }
    }
    #$windowitem{settings} = [settings_items()] if $restored{option};
    #$windowitem{budget}   = [budget_items()] if $restored{budget};
    %windowitem = init_windowitems();
    push @message, ["Restored.", "meta"];
    #my @sym = keys %stock;
    #push @message, ["Stocks: " . scalar @sym];
    close SAV;
    debuglog("Restored ($_): $restored{$_}") for sort { $a cmp $b } keys %restored;
  } else {
    debuglog("Cannot read from save game file '$fn': $!");
  }
}

sub savegame {
  my $fn = $option{savefile} || catfile(get_config_dir(), "eggs.save");
  open SAV, ">", $fn or die "Cannot write to save game file '$fn': $!";
  print SAV "Eggs v" . $version . " Saved Game\n";
  print SAV qq[#### Globals\n];
  for my $d (["Date", $date],
             ["RunStarted", $runstarted],
             ["NGPETA", $ngpeta],
             ["BirthDate", $birthdate],
            ) {
    my ($name, $dt) = @$d;
    print SAV "Global:" . $name . "=" . sprintf("%04d", $dt->year()) . "-" . sprintf("%02d", $dt->month()) . "-" . sprintf("%02d", $dt->mday()) . "\n";
  }
  print SAV qq[Global:Cash=] . $cash . " zorkmids\n";
  print SAV qq[Global:Debt=] . $debt . " trillion zm at " . $creditrating . "\n";
  print SAV qq[Global:Primerate=] . $primerate . "%\n";
  print SAV qq[Global:Lvl=] . (join ",", map { 0 + $_ } ($breedlvl, $genlvl, $genleak, $gamephase)) . "\n";
  print SAV qq[#### Assets\n];
  for my $atype (sort { ($asset{$a}{sort} || $asset{$a}{value}) <=> ($asset{$b}{sort} || $asset{$b}{value}) } keys %asset) {
    my $unl = (ref $asset{$atype}{unlocked}{buy})
      ? qq[unlocked.buy=] . join(",", grep { $asset{$atype}{unlocked}{buy}{$_}
                                           } keys %{ $asset{$atype}{unlocked}{buy}})
      : "";
    my $trk = join(";", map {
      my $g = $_;
      join ",", map { $$g{$_} } qw(qtty year month expire since);
    } @{$asset{$atype}{agegroup}});
    my $an  = $asset{$atype}{asneeded} ? "asneeded=buy" : "";
    print SAV qq[Asset:$atype=$asset{$atype}{qtty};$an;$unl;$trk\n];
  }
  print SAV qq[#### Cashflow Section\n];
  print SAV qq[Mode:$$wcashflow{subtype}=$$wcashflow{mode}\n];
  for my $k (qw(current lastmonth year lastyear total)) {
    print SAV qq[CF:$k:] . join(",", map { $_ . "=" . $cashflow{$k}{$_} } keys %{$cashflow{$k}}) . "\n";
    for my $cat (keys %{$cashflow{sc}{$k}}) {
      print SAV qq[CFSC:$k:$cat:] . (join(",", map {
        $_ . "=" . $cashflow{sc}{$k}{$cat}{$_}
      } keys %{$cashflow{sc}{$k}{$cat}})) . "\n";
    }}
  print SAV qq[#### Budget Section\n];
  for my $bk (keys %budget) {
    print SAV qq[Budget:$bk:$budget{$bk}{value}\n];
    if ($budget{$bk}{progress}) {
      print SAV qq[Budgetted:$bk:$budget{$bk}{progress}\n];
    }
  }
  print SAV qq[#### Options Section\n];
  for my $o (grep { $$_{save} =~ /game/ } @option) {
    print SAV qq[Option:$$o{name}=$option{$$o{name}}\n];
  }
  print SAV qq[#### Investment Section\n];
  for my $k (keys %stock) {
    my $s = $stock{$k};
    print SAV qq[Stock:$k=$$s{name};$$s{industry};$$s{owned}/$$s{shares};$$s{price};$$s{sales};$$s{assets};$$s{cash};$$s{debt};$$s{idx};$$s{movement}\n];
  }
  for my $b (grep { $$_{mature} ge $date->ymd() } @bond) {
    my $idate = $$b{issued}->ymd();
    my $mdate = $$b{mature}->ymd();
    print SAV qq[Bond:$$b{id};$$b{issuer};$$b{amount};$idate;$mdate;$$b{rate}\n];
  }
  print SAV qq[#### Places Section\n];
  for my $p (@extantplace) {
    my $parent = $$p{parent} || "";
    print SAV qq[Place:$$p{type};$$p{name};$parent\n];
  }
  for my $c (@county) {
    print SAV qq[County:] . (join ";", map { $$c{$_}
                                           } qw(name capital capitalword licensed
                                                size owned_land available_land landcost parent))
      . "\n";
  }
  for my $p (@province) {
    print SAV qq[Province:] . (join ";", map { $$p{$_}
                                           } qw(name capital capitalword licensed
                                                size counties countysuff parent))
      . "\n";
  }
  for my $n (@nation) {
    print SAV qq[Nation:] . (join ";", map { $$n{$_}
                                           } qw(name capital capitalword licensed
                                                size provinces provincesuff parent))
      . "\n";
  }
  for my $w (@world) {
    print SAV qq[World:] . (join ";", map { $$w{$_}
                                          } qw(name capital capitalword licensed
                                               size nations parent))
      . "\n";
  }
  # TODO: larger jurisdictions
  print SAV qq[#### Messages Section\n];
  for my $m (@message) {
    my ($text, $channel) = @$m;
    $text =~ s/\n/ /g; # Messages _shouldn't_ have any newlines anyway.
    print SAV qq[Message:$channel:$text\n];
  }
  print SAV qq[#### EOF\n\n];
  close SAV;
  push @message, ["Saved.", "meta"];
  return;
}

#################################################################################################
#################################################################################################
###
###                                        D I S P L A Y :
###
#################################################################################################
#################################################################################################

sub changed_color_depth {
  redraw();
  color_test();
}

sub redraw {
  rewrap_message_log($wmessages);
  refreshscreen();         # Clear artifacts from $screen, and redo the layout.
  drawwidgets();           # Populate $screen
  draweggscreen();         # Actually draw $screen to terminal
}

sub draweggscreen {
  drawscreen($screen, %option);
  ## if ($option{nohome}) {
  ##   print $reset . "\n\n";
  ## } else {
  ##   print chr(27) . "[H" . $reset;
  ## }
  ## for my $y (0 .. $ymax) {
  ##   if (not ($y == $ymax)) {
  ##     print gotoxy(0, $y);
  ##     print $reset;
  ##   }
  ##   my $lastbg = "";
  ##   my $lastfg = "";
  ##   for my $x (0 .. $xmax) {
  ##     print "" . ((((($$s[$x][$y]{bg} || "") eq $lastbg) and
  ##                   (($$s[$x][$y]{fg} || "") eq $lastfg))
  ##                  ? "" : ((($$s[$x][$y]{bg} || "") . ($$s[$x][$y]{fg} || "")) || "")))
  ##              . (length($$s[$x][$y]{char}) ? ($$s[$x][$y]{char} || " ") : " ")
  ##       unless (($x == $xmax) and
  ##               ($y == $ymax) and
  ##               (not $option{fullrect}));
  ##     $lastbg = $$s[$x][$y]{bg} || "";
  ##     $lastfg = $$s[$x][$y]{fg} || "";
  ##   }
  ## }
}

sub refreshscreen {
  layout();
  $screen = +[
              map {
                [ map {
                  +{ char => "▒",
                     fg   => "grey",
                     bg   => "black",
                   };
                } 0 .. $ymax ]
              } 0 .. $xmax ];
}

sub layout {
  ($xmax, $ymax) = Term::Size::chars *STDOUT{IO};
  $xmax ||= 80;
  $ymax ||= 24;
  #$xmax--; $ymax--; # Term::Size::chars returns counts, not zero-indexed maxima.  Sometimes.  It's complicated, and confusing, and might depend on the terminal.
  $xmax = $option{xmax} if $option{xmax} and ($xmax > $option{xmax});
  $ymax = $option{ymax} if $option{ymax} and ($ymax > $option{ymax});
  my $leftsize  = ($xmax > 100) ? int($xmax / 5) : 20;
  my $rightsize = ($xmax > 100) ? int($xmax / 5) : 20;
  my $msgheight = int($ymax / 2); # TODO: maybe adjust this.
  my $budgetheight = 12;
  $wbg ||= +{ x => 1, y => 1, xmax => $xmax + 1, ymax => $ymax + 1,
              type    => "diffuse",
              fg      => "default",
              bg      => "default",
              id      => $wcount++,
              preseed => 7,
              redraw  => 1, };
  $wtopbar   = +{ type => "text", title => "Eggs Titlebar", redraw => 0,
                  text => join("", map { " " } 0 .. $xmax),
                  x => 0, y => 0, xmax => $xmax, ymax => 0,
                  bg => "brown", fg => "azure",
                  id => $wcount++,
                  #transparent => 0,
                };
  $wcashflow = +{ type => "egggame", subtype => "cashflow", title => "Cash Flow (F9)", mode => "",
                  redraw => 1, x => 0, y => 1, xmax => $leftsize - 1,
                  ymax => $ymax - 1,
                  fg => "gold", focusbg => 'brown', id => $wcount++, transparent => 1,
                  input => sub { input_cashflow(@_); },
                  onscroll => sub { eggwidget_onscroll(@_) },
                  helpinfo => [ qq[Press s, b, e, i, or p to view details about sales, budget expenses, essentials, investments, or purchases, respectively.],
                                qq[Press o to return to the overview.],
                              ],
                };
  $wmessages = +{ type => "messagelog", subtype => "messages", title => "Messages (F8)", redraw => 1,
                  x => $leftsize, y => 1, xmax => $xmax - $rightsize - 2, ymax => $msgheight,
                  messages => \@message, lines => \@messageline,
                  msgpos => 0, linepos => 0, xpos => 0,
                  fg => "spring green", focusbg => "grey", id => $wcount++,
                  input => sub { input_messagelog(@_); },
                  onscroll => sub { messagelog_onscroll(@_) },
                  transparent => 1,
                  helpinfo => [ qq[Use arrow keys or PgUp, PgDn to scroll.],
                                qq[Home or End to jump to the beginning or end.],
                              ],
                };
  $wassets = +{ type => "egggame", subtype => "assets", title => "Assets (F7)", redraw => 1,
                x => $xmax - $rightsize - 1, xmax => $xmax, fg => "indigo", focusbg => "red",
                y => 1, ymax => $ymax - $budgetheight, id => $wcount++, transparent => 1,
              };
  $wbudget = +{ type => "egggame", subtype => "budget", title => "Budget (F6)", redraw => 1,
                x => $xmax - $rightsize - 1, xmax => $xmax,
                y => $ymax - $budgetheight, ymax => $ymax - 1,
                fg => "purple-red", focusbg => "purple", id => $wcount++, transparent => 1,
                input => sub { input_budget(@_); },
                onscroll => sub { eggwidget_onscroll(@_) },
              };
  if ($option{debug}) {
    $wordkey = +{ type => "ordkey", title => "OrdKey F12", redraw => 1,
                  line1 => "Press Keys",
                  x => $leftsize, y => $msgheight, xmax => $leftsize + 12, ymax => $ymax - 1,
                  input => sub { input_ordkey(@_); },
                  fg => "purple", #bg => "purple",
                  id => $wcount++,
                  transparent => 1,
                };
  }
  my $middlesize = $xmax - $leftsize - $rightsize - ($wordkey ? 12 : 0);
  my $buysize = int($middlesize * 3 / 5) - 1;
  $wbuy = +{ type => "egggame", subtype => "buy", title => "Buy (F3)", redraw => 1,
             x => $leftsize + ($wordkey ? 12 : 0), y => $msgheight, ymax => $ymax - 1,
             xmax => $leftsize + ($wordkey ? 12 : 0) + $buysize,
             input => sub { input_buy(@_); },
             onscroll => sub { eggwidget_onscroll(@_) },
             fg => "teal", focusbg => "cyan", id => $wcount++,
             transparent => 1,
           };
  $wsettings = +{ type => "egggame", subtype => "settings", title => "Settings (F10)", redraw => 1,
                  x => $leftsize + ($wordkey ? 12 : 0) + $buysize, y => $msgheight, ymax => $ymax - 1,
                  xmax => $xmax - $rightsize - 2,
                  input => sub { input_settings(@_); },
                  onscroll => sub { eggwidget_onscroll(@_) },
                  fg => "cyan", focusbg => "green", id => $wcount++,
                  transparent => 1,
                };
  $wticker = +{ type => "ticker", title => "Stock Ticker", redraw => 0,
                text => join("", map { " " } 0 .. $xmax),
                x => 0, y => $ymax - 1, xmax => $xmax, ymax => $ymax -1,
                bg => "blue", fg => "white", "pricefg" => "yellow",
                id => $wcount++,
              };
  $wfocus ||= $wbuy;
  $$wbg{disabled} = ($option{colordepth} >= 8) ? 0 : 1;
  @widget = grep { $_ and not $$_{disabled}
                 } ($wbg, $wtopbar, $wcashflow,
                    #$wgameclock, $wrealclock,
                    $wmessages, $wordkey, $wbuy, $wsettings,
                    $wassets, $wbudget, $wticker);
  for my $w (@widget) {
    $$w{contentsizex} ||= $$w{xmax} - $$w{x} - 2;
    $$w{contentsizey} ||= $$w{ymax} - $$w{y} - 2;
  }
}

sub color_test {
  push @message, ["Color Test: ", "meta"];
  for my $fg (grep { not ($$_{name} =~ /^diffuse/) } @namedcolor) {
    push @message, [$$fg{name}, $$fg{name}];
    # TODO: and show that on various backgrounds.
  }
}

## sub hsv2rgb {
##   my ($c) = @_;
##   use Imager::Color;
##   my $hsv = Imager::Color->new( hsv =>  [ $$c{h}, ($$c{v} / 100), ($$c{s} / 100) ] ); # hue, val, sat
##   ($$c{r}, $$c{g}, $$c{b}) = $hsv->rgba;
##   return $c;
## }

#################################################################################################
#################################################################################################
###
###                             S U P P O R T    F U N C T I O N S :
###
#################################################################################################
#################################################################################################

sub debuglog {
  my ($msg) = @_;
  if ($option{debug}) {
    #open DEBUG, ">>", "debug.log";
    #my $now = DateTime->now( time_zone => ($option{localtimezone} || UTC) );
    #print DEBUG $msg . "\n";
    #close DEBUG;
    egggamelog($msg);
  }
}

sub clog {
  my ($n) = @_;
  return log($n) / log(10);
}

sub isare {
  my ($num) = @_;
  return inflectverb($num, "is", "are");
}
sub inflectverb {
  my ($num, $sgverb, $plverb) = @_;
  return $sgverb if $num == 1;;
  return $plverb;
}

sub sgorpl { # Singular or plural, depending on number.
  my ($num, $noun, $pluralnoun) = @_;
  return $noun if $num == 1;
  return $pluralnoun || makeplural($noun);
}

sub makeplural {
  my ($noun) = @_;
  # Exceptions are handled by giving the asset an explicit plural when declaring it.
  # This function just has to handle the regular ones.
  if ($noun =~ /([sxz])$/) {
    return $noun . "es";
  } elsif ($noun =~ /([y])$/) {
    my $p = $noun;
    $p =~ s/y$/ies/;
    return $p;
  }
  return $noun . "s";
}

sub commalist {
  my (@item) = @_;
  if (2 >= scalar @item) {
    return join " and ", @item;
  }
  my $last = pop @item;
  my $rest = join ", ", @item;
  return join ", and ", $rest, $last;
}

sub shownum {
  my ($n) = @_;
  my $sign = ($n >= 0) ? "" : "-";
  $n = abs($n);
  if ($n > 10 * 1000 * 1000 * 1000 * 1000 * 1000 * 1000) {
    # Over 10 quintillion, not actually possible on a 64-bit system without a bignum library.
    # At some point I will have to do something about that, probably use bignum;
    my $exp = 0;
    my $base = $n;
    while ($base > 1000) {
      $exp += 3;
      $base = int(($base + 500) / 1000);
    }
    while ($base >= 10) {
      $exp++;
      $base = int($base + 4.999) / 10;
    }
    return $sign . $base . "e+0" . $exp; # scientific notation
  } elsif ($n > 100 * 1000 * 1000 * 1000 * 1000 * 1000 * 1000) {
    my $q = int(($n + 500 * 1000 * 1000 * 1000 * 1000 * 1000) / (1000 * 1000 * 1000 * 1000 * 1000 * 1000));
    return $sign . $q . "q"; # quadrillion
  } elsif ($n >  10 * 1000 * 1000 * 1000 * 1000 * 1000) {
    my $q = int(($n + 500 * 1000 * 1000 * 1000 * 1000) / (100 * 1000 * 1000 * 1000 * 1000)) / 10;
    return $sign . $q . "q"; # quadrillion
  } elsif ($n > 100 * 1000 * 1000 * 1000 * 1000) {
    my $t = int(($n + 500 * 1000 * 1000 * 1000) / (1000 * 1000 * 1000 * 1000));
    return $sign . $t . "t"; # trillion
  } elsif ($n >  10 * 1000 * 1000 * 1000 * 1000) {
    my $t = int(($n + 500 * 1000 * 1000 * 1000) / (100 * 1000 * 1000 * 1000)) / 10;
    return $sign . $t . "t"; # trillion
  } elsif ($n > 100 * 1000 * 1000 * 1000) {
    my $b = int(($n + 500 * 1000 * 1000) / (1000 * 1000 * 1000));
    return $sign . $b . "b"; # billion
  } elsif ($n >  10 * 1000 * 1000 * 1000) {
    my $b = int(($n + 500 * 1000 * 1000) / (100 * 1000 * 1000)) / 10;
    return $sign . $b . "b"; # billion
  } elsif ($n > 100 * 1000 * 1000) {
    my $m = int(($n + 500000) / (1000 * 1000));
    return $sign . $m . "m"; # million
  } elsif ($n >  10 * 1000 * 1000) {
    my $m = int(($n + 500000) / (100 * 1000)) / 10;
    return $sign . $m . "m"; # million
  } elsif ($n > 100 * 1000) {
    my $m = int(($n + 500) / 1000);
    return $sign . $m . "k"; # k=thousand
  } elsif ($n >  10 * 1000) {
    my $m = int(($n + 500) / 100) / 10;
    return $sign . $m . "k"; # k=thousand
  } elsif ($n >= 1000) {
    return $sign . int $n;
  } elsif ($n >= 100) {
    return $sign . (int($n * 10) / 10);
  } elsif ($n >= 10) {
    return $sign . (int($n * 100) / 100);
  } elsif ($n >= 1) {
    return $sign . (int($n * 1000) / 1000);
  } elsif ($n == 0) {
    return $n;
  } else { # scientific notation.
    my $exp = 0;
    while (abs($n) < 1) {
      $exp++;
      $n = $n * 10;
    }
    return $sign . ((int($n * 1000) / 1000) . "E-" . sprintf("%02d", $exp));
  }
}

sub randomorder {
  my (@item) = @_;
  return map {
    $$_[0]
  } sort {
    $$a[1] <=> $$b[1]
  } map {
    [$_ => rand(65535) ]
  } @item;
}

sub uniq {
  my (@item) = @_;
  my %seen;
  return grep { not $seen{$_}++ } @item;
}

sub uptime {
  local %ENV; delete $ENV{PATH};
  my $ut = `/usr/bin/uptime`;
  chomp $ut;
  $ut =~ /(up (?:\d+ \w+,?\s*\d*[:]?\d*(?: min)?)|\d+[:]?\d*(?: min)?),\s+(\d+\s+users?),\s+load average[:]\s+([0-9.]+),\s+([0-9.]+),\s+([0-9.]+)/;
  my ($up, $users, $loadone, $loadtwo, $loadthree) = ($1, $2, $3, $4, $5);
  if (wantarray) { return ($up, $users, $loadone, $loadtwo, $loadthree); }
  else { return $ut }
}

sub diffuse_scale {
  my ($v) = @_;
  return 0 if $v <= 0;
  my $ln = log($v * 1000);
  my $sqr = $ln * $ln;
  if ($sqr > 255) {
    return 255;
  } else {
    return int $sqr;
  }
}

sub valuefromexpectations {
  my ($ev, $chances) = @_;
  # $ev is a percentage success probability per opportunity.
  # ($ev can be higher than 1 if a multiple outcome is possible from a single chance).
  # $chances is the number of opportunities.
  if ($chances < 100) {
    # base case, just iterate it out:
    my $total = 0;
    for (1 .. $chances) {
      $total += int($ev / 100);
      $total++ if (($ev % 100) > rand 100);
    }
    return $total;
  }
  # If we're doing a lot of instances, we don't wanna iterate it out,
  # because performance.  But we don't wanna just calculate it in a
  # single step, because there won't be enough variation.  We want the
  # output to center around the expectation but vary a bit, and we
  # want to accomplish this in no worse than O(log(n)) time for large
  # n.  (For small n, performance isn't a problem.)  The following
  # algorithm is not ideal, but it'll do for an idle game (which is my
  # way of saying I can't be bothered to look up or think up a really
  # correct algorithm at the moment).
  my $portion = int($chances / 10);
  my $result  = valuefromexpectations($ev, $chances - (9 * $portion));
  for (1 .. 9) {
    my $partial = int((($ev * $portion) + 50) / 100);
    if ($ev >= rand(100)) {
      $partial += int($partial / 10);
    } else {
      $partial -= int($partial / 10);
    }
    $result += $partial;
  }
  return $result;
}

