require 'spec_helper'

require 'bot/job_options_parser'

describe JobOptionsParser do
  let(:parser) { JobOptionsParser.new }

  it 'recognizes --phantomjs' do
    parser.parse('--phantomjs')[:phantomjs].should be_true
  end

  it 'parses --ignore-sets=A,B to an array' do
    parser.parse('--ignore-sets=A,B')[:ignore_sets].should == ['A', 'B']
  end

  it 'recognizes --pipeline=ID' do
    parser.parse('--pipeline=ID')[:pipeline].should == 'ID'
  end

  describe 'when unknown options are present' do
    it 'raises UnknownOptionError' do
      lambda { parser.parse('--foo=bar') }.should raise_error(JobOptionsParser::UnknownOptionError)
    end

    it 'returns the unknown option in the exception message' do
      begin
        parser.parse('--foo=bar')
      rescue JobOptionsParser::UnknownOptionError => e
        ex = e
      end

      ex.message.should =~ /--foo/
    end
  end
end
