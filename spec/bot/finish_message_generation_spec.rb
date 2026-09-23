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
            'foobar: Your job for http://www.example.org has finished. csu70nsn5y3k1jop4q6uptgyp'
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
            'foobar: Your job for http://www.example.org was aborted. csu70nsn5y3k1jop4q6uptgyp'
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
            'foobar: Your job for http://www.example.org has finished. csu70nsn5y3k1jop4q6uptgyp'
          ],
          '#grault' => [
            'quxbaz: Your job for http://www.example.net has finished. eywnxrf47xues9acq6xmy7xun'
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

      it 'returns two messages with URLs' do
        messages_by_channel = vessel.generate_messages(infos)

        messages_by_channel['#quux'].sort.should == [
          'foobar: Your job for http://www.example.net has finished. eywnxrf47xues9acq6xmy7xun',
          'foobar: Your job for http://www.example.org has finished. csu70nsn5y3k1jop4q6uptgyp'
        ]
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

      it 'returns four messages with URLs' do
        messages_by_channel = vessel.generate_messages(infos)

        messages_by_channel['#quux'].sort.should == [
          'foobar: Your job for http://www.example.biz was aborted. 12pjidkef5awcinlco5ol57xv',
          'foobar: Your job for http://www.example.com was aborted. f4pg9usx4j96ki3zczwlczu51',
          'foobar: Your job for http://www.example.net has finished. eywnxrf47xues9acq6xmy7xun',
          'foobar: Your job for http://www.example.org has finished. csu70nsn5y3k1jop4q6uptgyp'
        ]
      end
    end
  end
end
