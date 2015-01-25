require 'spec_helper'

require 'bot/command_patterns'

describe CommandPatterns do
  describe 'Archive command' do
    let(:regex) { CommandPatterns::ARCHIVE }

    it 'strips excess spaces' do
      md = regex.match "!archive     http://www.example.com/     "

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !archive URL' do
      md = regex.match "!archive http://www.example.com/"

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !firstworldproblems URL' do
      md = regex.match "!firstworldproblems http://www.example.com/"

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !a URL' do
      md = regex.match "!a http://www.example.com/"

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !a URL--ignores=blogs as a URL' do
      md = regex.match "!a http://www.example.com/--ignores=blogs"

      md[1].should == 'http://www.example.com/--ignores=blogs'
    end

    it 'recognizes !a URL --ignores=blogs' do
      md = regex.match "!a http://www.example.com/ --ignores=blogs"

      md[1].should == 'http://www.example.com/'
      md[2].should == '--ignores=blogs'
    end

    it 'recognizes !a URL --ignores=blogs --someother=param' do
      md = regex.match "!a http://www.example.com/ --ignores=blogs --someother=param"

      md[1].should == 'http://www.example.com/'
      md[2].should == '--ignores=blogs --someother=param'
    end

    it 'does not recognize !a < URL' do
      md = regex.match '!a < http://www.example.com/urls.txt'

      md.should be_nil
    end
  end

  describe 'Archiveonly command' do
    let(:regex) { CommandPatterns::ARCHIVEONLY }

    it 'strips excess spaces' do
      md = regex.match "!archiveonly     http://www.example.com/     "

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !archiveonly URL' do
      md = regex.match "!archiveonly http://www.example.com/"

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !ao URL' do
      md = regex.match "!ao http://www.example.com/"

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !ao URL--ignores=blogs as a URL' do
      md = regex.match "!ao http://www.example.com/--ignores=blogs"

      md[1].should == 'http://www.example.com/--ignores=blogs'
    end

    it 'recognizes !ao URL --ignores=blogs' do
      md = regex.match "!ao http://www.example.com/ --ignores=blogs"

      md[1].should == 'http://www.example.com/'
      md[2].should == '--ignores=blogs'
    end

    it 'recognizes !ao URL --ignores=blogs --someother=param' do
      md = regex.match "!ao http://www.example.com/ --ignores=blogs --someother=param"

      md[1].should == 'http://www.example.com/'
      md[2].should == '--ignores=blogs --someother=param'
    end

    it 'does not recognize !ao < URL' do
      md = regex.match '!ao < http://www.example.com/urls.txt'

      md.should be_nil
    end

    it 'does not recognize !archiveonly < URL' do
      md = regex.match '!archiveonly < http://www.example.com/urls.txt'

      md.should be_nil
    end
  end

  describe '!a < command' do
    let(:regex) { CommandPatterns::ARCHIVE_FILE }

    it 'strips excess spaces' do
      md = regex.match "!a <     http://www.example.com/     "

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !a < http://www.example.com/urls.txt' do
      md = regex.match '!a < http://www.example.com/urls.txt'

      md[1].should == 'http://www.example.com/urls.txt'
    end
  end

  describe '!ao < command' do
    let(:regex) { CommandPatterns::ARCHIVEONLY_FILE }

    it 'strips excess spaces' do
      md = regex.match "!ao <     http://www.example.com/     "

      md[1].should == 'http://www.example.com/'
    end

    it 'recognizes !archiveonly < http://www.example.com/urls.txt' do
      md = regex.match '!archiveonly < http://www.example.com/urls.txt'

      md[1].should == 'http://www.example.com/urls.txt'
    end

    it 'recognizes !ao < http://www.example.com/urls.txt' do
      md = regex.match '!ao < http://www.example.com/urls.txt'

      md[1].should == 'http://www.example.com/urls.txt'
    end
  end

  describe '!ig command' do
    let(:regex) { CommandPatterns::IGNORE }

    it 'strips excess spaces' do
      md = regex.match "!ig       foobar     barbaz    "

      md[1].should == 'foobar'
      md[2].should == 'barbaz'
    end
  end

  describe '!unig command' do
    let(:regex) { CommandPatterns::UNIGNORE }

    it 'strips excess spaces' do
      md = regex.match "!unig       foobar     barbaz    "

      md[1].should == 'foobar'
      md[2].should == 'barbaz'
    end
  end

  shared_examples_for 'a set delay command' do |cmd|
    it "recognizes #{cmd} IDENT MIN MAX" do
      md = regex.match "#{cmd} f4pg9usx4j96ki3zczwlczu51 500 750"

      md[1].should == 'f4pg9usx4j96ki3zczwlczu51'
      md[2].should == '500'
      md[3].should == '750'
    end

    it "does not recognize #{cmd} IDENT MIN MAX with non-integral numbers" do
      md = regex.match "#{cmd} f4pg9usx4j96ki3zczwlczu51 500.5 751.5"

      md.should be_nil
    end

    it "does not recognize negative delays" do
      md = regex.match "#{cmd} f4pg9usx4j96ki3zczwlczu51 500.5 -751.5"

      md.should be_nil
    end
  end

  describe 'Set delay command' do
    let(:regex) { CommandPatterns::SET_DELAY }

    it_should_behave_like 'a set delay command', '!delay'
    it_should_behave_like 'a set delay command', '!d'
  end

  describe 'Set concurrency command' do
    let(:regex) { CommandPatterns::SET_CONCURRENCY }

    it 'recognizes !concurrency IDENT LEVEL' do
      md = regex.match '!concurrency f4pg9usx4j96ki3zczwlczu51 8'

      md[1].should == 'f4pg9usx4j96ki3zczwlczu51'
      md[2].should == '8'
    end

    it 'recognizes !con IDENT LEVEL' do
      md = regex.match '!con f4pg9usx4j96ki3zczwlczu51 8'

      md[1].should == 'f4pg9usx4j96ki3zczwlczu51'
      md[2].should == '8'
    end
  end

  describe '!whereis command' do
    let(:regex) { CommandPatterns::WHEREIS }

    it 'recognizes !whereis IDENT' do
      md = regex.match '!whereis f4pg9usx4j96ki3zczwlczu51'

      md[1].should == 'f4pg9usx4j96ki3zczwlczu51'
    end

    it 'recognizes !w IDENT' do
      md = regex.match '!w f4pg9usx4j96ki3zczwlczu51'

      md[1].should == 'f4pg9usx4j96ki3zczwlczu51'
    end
  end
end
