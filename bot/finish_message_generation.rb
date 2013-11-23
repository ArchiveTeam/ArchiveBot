module FinishMessageGeneration
  def generate_messages(infos)
    # Group the completion data by channel.
    by_channel = infos.group_by { |info| info['started_in'] }

    # For each channel, group by user.
    by_channel.each_with_object({}) do |(channel, infos), h|
      by_user = infos.group_by { |info| info['started_by'] }

      list = []
      h[channel] = list

      # Now examine how many messages we have for each user.
      by_user.each do |user, infos|
        if infos.length == 1
          info = infos.first

          if info['aborted']
            list << "#{user}: Your job for #{info['url']} was aborted."
          else
            list << "#{user}: Your job for #{info['url']} has finished."
          end
        elsif infos.length > 1
          # Partition by abort status and print out just the counts.
          aborted, completed = infos.partition { |info| info['aborted'] }

          if completed.length > 0
            list << "#{user}: #{completed.length} of your jobs have finished."
          end

          if aborted.length > 0
            list << "#{user}: #{aborted.length} of your jobs were aborted."
          end
        end
      end
    end
  end
end
