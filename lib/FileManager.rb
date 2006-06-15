class FileManager
  
  @@icons = { 'pdf' => 'page_white_acrobat',
              'mp3' => 'music', 'wav' => 'music', 'acc' => 'music', 'ogg' => 'music',
              'doc' => 'page_white_word',
              'ppt' => 'page_white_powerpoint', 'pps' => 'page_white_powerpoint',
              'xls' => 'page_white_excel',
              'java' => 'page_white_cup', 'jar' => 'page_white_cup',
              'cc' => 'page_white_cplusplus', 'c++' => 'page_white_cplusplus',
              'cpp' => 'page_white_cplusplus',
              'cs' => 'page_white_csharp',
              'rb' => 'page_white_ruby',
              'c' => 'page_white_c',
              'zip' => 'page_white_compressed', 'gz' => 'page_white_compressed', 'tar' => 'page_white_compressed',
              'jpg' => 'page_white_camera', 'png' => 'page_white_camera',
              'gif' => 'page_white_camera', 'jpeg' => 'page_white_camera' }
              
  def FileManager.icon( extension ) 
    icn = @@icons[extension]
    icn = 'page_white' if icn.nil?
    return icn
  end
  
  def FileManager.base_part_of(file_name)
    name = File.basename(file_name)
    name.gsub(/[^\w._-]/, '')
  end
  
  def FileManager.size_text( size )
    if size.to_i < 1024
      "#{size}b"
    elsif size.to_i < 1024000
      "#{format('%0.2f',size.to_f/1024)}Kb"
    else
      "#{format('%0.2f',size.to_f/1024000)}Mb"
    end
  end
  
end