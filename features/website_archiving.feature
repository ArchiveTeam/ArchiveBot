Feature: Website archiving
  In order to save the Web from assholes
  As an Archive Team member
  I want to save a website
  So a copy of it exists before it completes its incredible journey

  @wip
  Scenario: Recursive archival saves all pages and requisites under a given path
    Given I am an IRC operator in #archivebot
    And there is a target at "http://localhost:4567/10/"

    When I run "!a http://localhost:4567/10/"

    Then ArchiveBot tells me "Archiving http://localhost:4567/10/"
    And ArchiveBot uploads a WARC to the upload staging site

# vim:ts=2:sw=2:et:tw=78
