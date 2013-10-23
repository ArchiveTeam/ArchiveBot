require 'spec_helper'

require 'command_patterns'

describe CommandPatterns do
  describe 'Archive command' do
    let(:regex) { CommandPatterns::ARCHIVE }

    it 'recognizes !archive URL' do
      md = regex.match "!archive http://www.example.com/"

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
  end

  describe 'Archiveonly command' do
    let(:regex) { CommandPatterns::ARCHIVEONLY }

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
  end
end
