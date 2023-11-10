#! /usr/bin/perl -Idebian/tests/lib

# check enforcement of basic username validity

use diagnostics;
use strict;
use warnings;

use AdduserTestsCommon;

#       from the useradd manual
#       --
#       It is usually recommended to only use usernames that begin with a lower
#       case letter or an underscore, followed by lower case letters, digits,
#       underscores, or dashes. They can end with a dollar sign. In regular
#       expression terms: [a-z_][a-z0-9_-]*[$]?

#       On Debian, the only constraints are that usernames must neither start
#       with a dash ('-') nor plus ('+') nor tilde ('~') nor contain a colon
#       (':'), a comma (','), or a whitespace (space: ' ', end of line: '\n',
#       tabulation: '\t', etc.). Note that using a slash ('/') may break the
#       default algorithm for the definition of the user's home directory.

use constant FAIL => 1;
use constant PASS => 2;
use constant BAD  => 4;
use constant ALL  => 8;
use constant FBAD => 16;
use constant ABAD => 32;

my %pat = (
    # Traditional Debian username patterns
    deb     => qr{^[a-z][a-z0-9_-]*\$?$},
    deb_sys => qr{^[a-z_][a-z0-9_-]*\$?$},
    # Bare minimum restrictions supported by useradd
    min     => qr{^[^-+~:,\s/][^:,\s/]*$},
    # Don't check anything!
    all     => qr{^.+$},
    # Debian minimum (adduser v3.122) IEEE Std 1003.1-2001
    ieee    => qr{^[A-Za-z0-9_.][-\@_.A-Za-z0-9]*\$?$},
    caps    => qr{^[A-Za-z0-9_.]+$}
);

test_name('12345', FAIL, FAIL|BAD, FAIL|FBAD, FAIL|ABAD, FAIL|ALL,
            $pat{min}, FAIL, FAIL|ALL);
test_name('1abc33', FAIL, PASS|BAD);
test_name('1abc33', FAIL, PASS|ABAD);
test_name('1abc33', FAIL, PASS|FBAD);
test_name('John.Smith', FAIL, PASS|BAD,
            $pat{ieee}, PASS,
            $pat{caps}, PASS);
test_name('John.Smith', FAIL, PASS|ABAD,
            $pat{ieee}, PASS,
            $pat{caps}, PASS);
test_name('John.Smith', FAIL, PASS|FBAD,
            $pat{ieee}, PASS,
            $pat{caps}, PASS);
test_name('alice_42', PASS,
            '^[a-z][a-z0-9]*$', FAIL, PASS|BAD, PASS|ABAD, PASS|FBAD);
test_name('user$', PASS,
            $pat{caps}, FAIL,
            $pat{ieee}, PASS);
test_name('_', PASS,
            $pat{ieee}, PASS,
            $pat{min}, PASS);
# this test is to see what backslash does
# unfortunately unpredictable
test_name("\}", FAIL, FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL,
            $pat{min}, PASS);
test_name("\\}", FAIL, FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL,
            $pat{min}, PASS);
# windows conventions
test_name('machine$', PASS,
            $pat{ieee}, PASS);
test_name('DOMAIN\user', FAIL, FAIL|BAD, FAIL|FBAD, FAIL|ABAD, PASS|ALL,
            $pat{min}, PASS);
test_name('user@email.example.com', FAIL, PASS|BAD, PASS|FBAD, PASS|ABAD, PASS|ALL,
            $pat{min}, PASS);

# test alternate escaping
test_name("'duke'", FAIL, FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL);
# the worst username possible
test_name("'c4\$h\\M0n3y\"'==>@", FAIL, FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL);

# should always fail any regex
my @fails = ('12345', 'root:root', 'test space', "test\nwhite\tspace",
    'a' x 33, 'ф' x 17);
test_name($_, FAIL, FAIL|BAD, FAIL|ABAD, FAIL|FBAD, FAIL|ALL,
            $pat{all}, FAIL, FAIL|ALL) for @fails;

# imho this should continue to fail; it may need
# special casing in creating home dirs if allowed
test_name("test/slash", FAIL,
            $pat{min}, FAIL, FAIL|BAD, FAIL|ABAD, FAIL|FBAD, FAIL|ALL);

# some stranger choices
test_name("ÿar",        FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL, $pat{min}, PASS);
test_name('*',          FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL, $pat{min}, PASS);
test_name('3>6',  FAIL, FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL, $pat{min}, PASS);
test_name('.com', FAIL, PASS|BAD, PASS|ABAD, PASS|FBAD, PASS|ALL, $pat{min}, PASS);
test_name('user%',      FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL, $pat{min}, PASS);
test_name('˄ʙɄȘ˳',      FAIL|BAD, FAIL|ABAD, FAIL|FBAD, PASS|ALL, $pat{min}, PASS);

# system users with leading underscores
test_name('_foo', PASS);
test_name('_foo-bar', PASS);

sub mode_string {
    my $mode = shift;
    my $mstr = '';
    $mstr .= ($mode & PASS) ? 'P' : '-';
    $mstr .= ($mode & FAIL) ? 'F' : '-';
    $mstr .= ($mode & BAD || $mode & FBAD || $mode & ABAD) ? 'B' : '-';
    $mstr .= ($mode & ALL) ? 'A' : '-';
    return $mstr;
}

# test_name(username, arg, arg....)
#
# arg may be:
#   - mode (FAIL, PASS, BAD, etc.; see constants above)
#   - regex (e.g., $pat{deb} or another member of %pat)
#
# The mode defaults to FAIL. The regex defaults to the adduser default for
# the SYS_NAME_REGEX setting.
sub test_name {
    my $username = shift;
    my $regex = (@_ && $_[0] !~ /^\d+$/) ? shift : undef;
    my $username_esc = $username;
    my $homedir = qq{/home/$username};
    my ($mode, $homedir_esc, @cmdargs);

    my $quot = q{'};
    if ($username_esc =~ /'/) {
        # FIXME: this quoting may still be incomplete
        $quot = q{"};
        $username_esc =~ s/([\$\"\\])/\\$1/g;
    }
    $homedir_esc = qq{${quot}/home/${username_esc}${quot}};
    $username_esc = qq{${quot}${username_esc}${quot}};

    my @cmd = ('/usr/sbin/adduser', '--quiet',
        '--ingroup', 'nogroup', '--system',
        '--disabled-password');

    do {
        $mode = (@_ && $_[0]=~ /^\d+$/) ? shift : FAIL;

        if (defined($regex)) {
            apply_config('SYS_NAME_REGEX', $regex);
        } else {
            # Regular expression is not provided. Write an empty configuration
            # file so that this test compares against the adduser default for the
            # SYS_NAME_REGEX setting.
            apply_config;
        }

        do {
            @cmdargs = ('--home', $homedir_esc);
            push @cmdargs, '--force-badname' if ($mode & FBAD);
            push @cmdargs, '--allow-bad-names' if ($mode & BAD);
            push @cmdargs, '--allow-badname' if ($mode & ABAD);
            push @cmdargs, '--allow-all-names' if ($mode & ALL);
            #print "\n\n".('     }'.('-'x20))."{ $username_esc [ ARGS ".join(' ', @cmdargs)."\n\n";

            # This is a dummy test to identify the following results.
            my $modestr = mode_string($mode);
            my $regexstr = defined($regex) ? $regex : 'SYS_NAME_REGEX';
            ok($regexstr, "testing [$modestr] $username =~ $regexstr");

            if ($mode & PASS) {
                assert_command_success_silent(@cmd, @cmdargs, $username_esc);
                assert_user_exists($username);
                assert_path_exists($homedir);
                assert_command_success_silent('/usr/sbin/deluser',
                    '--quiet', '--remove-home', $username_esc);
            } else {
                assert_command_failure_silent(@cmd, @cmdargs, $username_esc);
                assert_user_does_not_exist($username);
                assert_command_failure_silent('/usr/sbin/deluser',
                    '--quiet', '--remove-home', $username_esc);
            }
            $mode = (@_ && $_[0] =~ /^\d+$/ ) ? shift : undef;
        } while ($mode);

        $regex = shift || undef;
    } while (@_ || $regex);
}
