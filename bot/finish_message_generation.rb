module FinishMessageGeneration
  def generate_messages(infos)
    # Group the completion data by channel.
    by_channel = infos.group_by { |info| info['started_in'] }

    # For each channel, group by user.
    by_channel.each_with_object({}) do |(channel, infos), h|
      by_user = infos.group_by { |info| info['started_by'] }

      list = []
      h[channel] = list

      by_user.each do |user, infos|
        infos.each do |info|
          if info['aborted']
            list << "#{user}: Your job for #{info['url']} was aborted. #{info['ident']}"
          else
            list << "#{user}: Your job for #{info['url']} has finished. #{info['ident']}"
          end
        end
      end
    end
  end
end
