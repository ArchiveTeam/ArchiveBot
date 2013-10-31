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
end
