require 'spec_helper'

require 'bot/status_generator'

describe StatusGenerator do
  let(:sg) { StatusGenerator.new }

  shared_examples_for 'basic job data' do
    it 'returns the job ident'

    it 'returns the job URL'

    it 'returns the amount of data downloaded'

    it 'returns the number of errors encountered'
  end

  describe '#by_ident' do
    describe 'for a running job' do
      include_examples 'basic job data'

      it 'returns status as :running'
    end

    describe 'for a finished job' do
      include_examples 'basic job data'

      it 'returns status as :finished'

      describe 'if one archive URL exists' do
        it 'returns the archive URL'
      end
    end
  end

  describe '#by_url' do
    describe 'for a running job' do
      include_examples 'basic job data'

      it 'returns status as :running'
    end

    describe 'for a finished job' do
      include_examples 'basic job data'

      it 'returns status as :finished'

      describe 'if one archive URL exists' do
        it 'returns the archive URL'
      end
    end
  end
end
