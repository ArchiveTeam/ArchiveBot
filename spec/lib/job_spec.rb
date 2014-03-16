require 'spec_helper'

require 'lib/job'

describe Job do
  describe '#ident' do
    it 'generates an identity on the normalized URL' do
      j1 = Job.new(URI('http://www.example.com'))
      j2 = Job.new(URI('http://www.example.com/'))

      j1.ident.should == j2.ident
    end
  end

  describe '#from_hash' do
    it 'reads a job with a nil finished_at as not finished' do
      j = Job.new
      j.from_hash('finished_at' => nil)

      j.should_not be_finished
    end

    it "presents a job's finished_at timestamp as an integer" do
      j = Job.new
      j.from_hash('finished_at' => 1234567890)

      j.finished_at.should == 1234567890
    end
  end
end
