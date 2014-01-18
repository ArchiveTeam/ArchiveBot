require 'spec_helper'

require 'cogs/ignore_pattern_id_generation'

describe IgnorePatternIdGeneration do
  describe '#id_from_path' do
    let(:vessel) do
      Object.new.extend(IgnorePatternIdGeneration)
    end

    describe 'with an absolute path' do
      let(:path) { '/home/foo/bar/ignore_patterns/blogs.json' }

      it 'constructs the ID ignore_patterns:BASENAME' do
        vessel.id_from_path(path).should == 'ignore_patterns:blogs'
      end
    end
  end
end
