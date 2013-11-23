require 'spec_helper'

require 'bot/finish_message_generation'

describe FinishMessageGeneration do
  let(:vessel) do
    Object.new.extend(FinishMessageGeneration)
  end

  describe '#generate_messages' do
    describe 'with one job for one person' do
      let(:infos) do
        [
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.org',
          }
        ]
      end

      it 'returns a message with the URL' do
        vessel.generate_messages(infos).should == {
          '#quux' => [
            'foobar: Your job for http://www.example.org has finished.'
          ]
        }
      end
    end

    describe 'with an aborted job' do
      let(:infos) do
        [
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.org',
            'aborted' => true
          }
        ]
      end

      it 'returns a message with the URL' do
        vessel.generate_messages(infos).should == {
          '#quux' => [
            'foobar: Your job for http://www.example.org was aborted.'
          ]
        }
      end
    end

    describe 'with one job per person for two people' do
      let(:infos) do
        [
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.org',
            'finished_at' => 1234567890
          },
          { 'started_by' => 'quxbaz',
            'started_in' => '#grault',
            'url' => 'http://www.example.net',
            'finished_at' => 1234567890
          }
        ]
      end

      it 'returns two messages with URLs' do
        vessel.generate_messages(infos).should == {
          '#quux' => [
            'foobar: Your job for http://www.example.org has finished.'
          ],
          '#grault' => [
            'quxbaz: Your job for http://www.example.net has finished.'
          ]
        }
      end
    end

    describe 'with two jobs for one person' do
      let(:infos) do
        [
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.org'
          },
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.net'
          }
        ]
      end

      it 'returns a message with the job completion count' do
        vessel.generate_messages(infos).should == {
          '#quux' => [
            'foobar: 2 of your jobs have finished.'
          ]
        }
      end
    end

    describe 'with multiple aborts and completes for the same person' do
      let(:infos) do
        [
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.org'
          },
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.com',
            'aborted' => true
          },
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.net'
          },
          { 'started_by' => 'foobar',
            'started_in' => '#quux',
            'url' => 'http://www.example.biz',
            'aborted' => true
          },
        ]
      end

      it 'returns one message with counts' do
        vessel.generate_messages(infos).should == {
          '#quux' => [
            'foobar: 2 of your jobs have finished.',
            'foobar: 2 of your jobs were aborted.'
          ]
        }
      end
    end
  end
end
