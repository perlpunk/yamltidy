# How to contribute

This module uses Dist::Zilla for creating releases, but you should
be able to develop and test it without Dist::Zilla.

## Commits

I try to follow these guidelines:

* Git commits
  * Short commit message headline (if possible, up to 60 characters)
  * Blank line before message body
  * Message should be like: "Add foo ...", "Fix ..."
  * If you need to do formatting changes like indentation, put them
    into their own commit
* Git workflow
  * Rebase every branch before merging it with --no-ff. Rebasing your
    pull request to current master helps me merging it.
  * No merging master into branches - try to rebase always
  * User branches might be heavily rebased/reordered/squashed because
    I like a clean history


## Code

* No Tabs please
* No trailing whitespace please
* Perl: 4 spaces indentation
* YAML: see .yamltidy ;-)
* Look at existing code for formatting ;-)

## Testing

    # Checkout yaml-test-suite
    make -f Makefile.dev yts
    prove -lr t xt

You can check test coverage with

    make -f Makefile.dev cover

## Contact

Email: tinita at cpan.org
IRC: tinita on freenode and irc.perl.org

Chances are good that contacting me on IRC is the fastest way.
