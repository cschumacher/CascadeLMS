require 'SimpleProgramRunner'
require 'FileManager'

class Instructor::TurninsController < Instructor::InstructorBase
  
  before_filter :ensure_logged_in
  before_filter :set_tab
  
  layout 'application'
  
  
  def index
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_grade_individual', 'ta_view_student_files', 'ta_grade_individual' )
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    # load the students
    @students = @course.students
    
    if @assignment.enable_journal
      # count journals
      @journal_count = Hash.new
      @students.each do |s|
        @journal_count[s.id] = Journal.count( :conditions => ["user_id=? and assignment_id=?", s.id, @assignment.id ] )
      end
    end
    
    @any_turnins = false
    if @assignment.use_subversion || @assignment.enable_upload
      # see if turnins
      @turnin_sets = Hash.new
      @students.each do |s|
        @turnin_sets[s.id] = UserTurnin.count( :conditions => ["user_id=? and assignment_id=?", s.id, @assignment.id ] ) > 0
        @any_turnins = @any_turnins || @turnin_sets[s.id]
      end
    end
    
    # load grades
    @grade_item = GradeItem.find(:first, :conditions => ["assignment_id = ?", @assignment.id] )
    if @grade_item
      @grades = Hash.new
      entries = GradeEntry.find(:all, :conditions => ["grade_item_id=?", @grade_item.id ] )
      entries.each do |e|
        @grades[e.user_id] = e.points
      end
    end
    
    @title = "Turnins for #{@assignment.title}"
  end
  
  def toggle_released
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    return unless course_open( @course, :action => 'index' )
    
    @assignment.released = !@assignment.released
    
    
    unless @assignment.save
      flash[:badnotice] = "Error changing assignment comments status."
    end
    
    unless @assignment.grade_item.nil?
      @assignment.grade_item.visible = @assignment.released
      @assignment.grade_item.save
    end
      
    redirect_to :action => 'index', :course => @course, :assignment => @assignment
  end
  
  def rollback
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    # make sure the student exists
    @student = User.find(params[:id])
    if ! @student.student_in_course?( @course.id )
      flash[:badnotice] = "Invalid student record requested."
      redirect_to :action => 'index'
    end
    
    # get turn-in sets
    @turnins = UserTurnin.find(:all, :conditions => ["user_id=? and assignment_id=?", @student.id, @assignment.id ], :order => "position DESC" )
    @current_turnin = @turnins[0] rescue @current_turnin = nil
   
    if @current_turnin.user_turnin_files.size == 1
      @current_turnin.destroy
    else
      flash[:badnotice] = "Can not rollback the current turn-in set for this student, it is not empty."
    end
    
    redirect_to :action => 'view_student', :course => @course, :assignment => @assignment, :id => @student
  end
  
  def view_student
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    # make sure the student exists
    @student = User.find(params[:id])
    if ! @student.student_in_course?( @course.id )
      flash[:badnotice] = "Invalid student record requested."
      redirect_to :action => 'index'
    end
    
    # get grade
    # load grades
    @grade_item = GradeItem.find(:first, :conditions => ["assignment_id = ?", @assignment.id] )
    if @grade_item
      @grade_entry = GradeEntry.find(:first, :conditions => ["grade_item_id=? and user_id=?", @grade_item.id, @student.id ] )
      unless @grade_entry
        @grade_entry = GradeEntry.new
      end
    end
    
    # get journals
    @journals = Journal.find(:all, :conditions => ["user_id=? and assignment_id=?", @student.id, @assignment.id ], :order => "start_time ASC" )
   
    # get turn-in sets
    @turnins = UserTurnin.find(:all, :conditions => ["user_id=? and assignment_id=?", @student.id, @assignment.id ], :order => "position DESC" )
    @current_turnin = @turnins[0] rescue @current_turnin = nil
    @display_turnin = @current_turnin
    
    if params[:ut]
      @turnins.each { |x| @display_turnin = x if x.id == params[:ut].to_i }
    end
    
    if @assignment.enable_journal
     if @assignment.journal_field.start_time && @assignment.journal_field.end_time
      # calculate time
      elapsed = 0;
      @journals.each do |journal|
        elapsed += journal.end_time - journal.start_time - journal.interruption_time*60
      end
      elapsed = (elapsed / 60).truncate #down to minutes
      @minutes = elapsed % 60
      elapsed -= @minutes

      @days = (elapsed / 1440).truncate
      elapsed -= @days * 1440

      @hours = (elapsed / 60).truncate
     end
    end 
    
    @title = "#{@student.display_name} (#{@student.uniqueid}) - #{@assignment.title}"
    
  end
  
  def submit_grade
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @student = User.find( params[:id] )
    if ! @student.student_in_course?( @course.id )
      flash[:badnotice] = "Invalid student record requested."
      redirect_to :action => 'index'
    end
    
    # get grade
    # load grades
    @grade_item = GradeItem.find(:first, :conditions => ["assignment_id = ?", @assignment.id] )
    if @grade_item
      @grade_entry = GradeEntry.find(:first, :conditions => ["grade_item_id=? and user_id=?", @grade_item.id, @student.id ] )
      if @grade_entry
        @grade_entry.update_attributes( params[:grade_entry] )
      else
        @grade_entry = GradeEntry.new( params[:grade_entry] )
        @grade_entry.course = @course
        @grade_entry.user = @student
        @grade_entry.grade_item = @grade_item
      end
      
      @grade_entry.points = 0 if @grade_entry.points.to_s.eql?('')
      
      if @grade_entry.points < 0
        @grade_entry.destroy
        @grade_entry = nil
      end
    else 
      flash[:badnotice] = "Application error - there is not grade item for this assignment.  Set on up in the GradeBook."
    end
    
    if @grade_entry.nil?
      flash[:notice] = "Grade for '#{@student.display_name}' has been deleted for this assignment (Since no point value was entered)."
    elsif @grade_entry.save
      flash[:notice] = "Grade for '#{@student.display_name}' has been updated to '#{@grade_entry.points}' for this assignment."
    else
      flash[:badnotice] = "Error updating student grade - results not saved."
    end
    redirect_to :action => 'view_student', :id => @student
  end
  
  def download_all_files
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    ## create temp file for the archive
    tf = TempFiles.new
    tf.filename = "#{@app['temp_dir']}/#{@user.uniqueid}_assignment_#{@assignment.id}_all_files.tar.gz"
    tf.save_until = Time.now + 60*24*24
    tf.save
    
    ## copy each of the latest turnins to a central point
    temp_dir = "#{@app['temp_dir']}/"
    file_tmp_dir = "#{Time.now.to_i}_#{@user.uniqueid}_assignment_#{@assignment.id}"
    
    FileUtils.mkdir_p( "#{temp_dir}#{file_tmp_dir}" )
    
    students = @course.students
    # copy turnins
    students.each do |s|
      uts = UserTurnin.find(:first, :conditions => ["user_id=? and assignment_id=?", s.id, @assignment.id ], :order => "created_at desc" )
      FileUtils.mkdir_p( "#{temp_dir}#{file_tmp_dir}/#{s.uniqueid}" )
      unless uts.nil?
        dir = uts.get_dir("#{@app['external_dir']}")
        command = "cd #{dir}; cp -R * #{temp_dir}#{file_tmp_dir}/#{s.uniqueid}"
        result = `#{command} 2>&1`
      end
    end
    
    
    #directory = @turnin.get_dir( @app['external_dir'] )
    #last_part = directory[directory.rindex('/')+1...directory.size]
    #first_part = directory[0...directory.rindex('/')]
    
    tar_cmd = "cd #{temp_dir}#{file_tmp_dir}; tar -czf #{tf.filename} *"
    #puts "#{tar_cmd}"
    result = `#{tar_cmd} 2>&1`
  
    if result.size > 0 
      flash[:badnotice] = "There was an error creating the download file, please try again later."
      redirect_to :action => 'index', :id => nil
      return
    end
  
    begin  
      send_file tf.filename, :filename => "#{@user.uniqueid}_assignment_#{@assignment.id}_all_files.tar.gz"
      rescue
        flash[:badnotice] = "There was an error creating the download file, please try again later."
        redirect_to :action => 'view_student', :id => @turnin.user_id
      
    end
    
    # cleanup 
    result = `cd #{temp_dir}; rm -r #{file_tmp_dir}`
  end
  
  def download_set
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @turnin = UserTurnin.find( params[:id] ) rescue @turnin = UserTurnin.new
    return unless turnin_for_assignment( @turnin, @assignment )
    
    tf = TempFiles.new
    tf.filename = "#{@app['temp_dir']}/#{@user.uniqueid}_assignment_#{@assignment.id}_turnin_#{@turnin.id}.tar.gz"
    tf.save_until = Time.now + 60*24*24
    tf.save
    
    directory = @turnin.get_dir( @app['external_dir'] )
    last_part = directory[directory.rindex('/')+1...directory.size]
    first_part = directory[0...directory.rindex('/')]
    
    tar_cmd = "tar -C #{first_part} -czf #{tf.filename} #{last_part}"
    result = `#{tar_cmd} 2>&1`
    
    if result.size > 0 
      flash[:badnotice] = "There was an error creating the download file, please try again later."
      redirect_to :action => 'index', :id => nil
      return
    end
    
    begin  
      send_file tf.filename, :filename => "#{@user.uniqueid}_assignment_#{@assignment.id}_turnin_#{@turnin.id}.tar.gz"
    rescue
      flash[:badnotice] = "There was an error creating the download file, please try again later."
      redirect_to :action => 'view_student', :id => @turnin.user_id
    end   
    
  end
  
  def download_file
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @utf = UserTurninFile.find( params[:id] )  
    return unless turnin_file_downloadable( @utf )
    @turnin = @utf.user_turnin 
    return unless turnin_for_assignment( @turnin, @assignment )
    
    # get the file and download it :)
    directory = @turnin.get_dir( @app['external_dir'] )
    
    # resolve file name
    relative_name = @utf.filename
    walker = @utf
    while walker.directory_parent > 0 
      walker = UserTurninFile.find( walker.directory_parent )
      relative_name = "#{walker.filename}/#{relative_name}"
    end
    
    filename = "#{directory}#{relative_name}"
    
    begin  
      send_file filename, :filename => @utf.filename
    rescue
      flash[:badnotice] = "Sorry - the requested document has been deleted or is corrupt.  Please notify your system administrator if this problem continues."
      redirect_to :action => 'view_student', :course => @course, :assignment => @assignment, :id => @utf.user_id
    end
  end
  
  def file_comment
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @utf = UserTurninFile.find( params[:id] )  
    return unless turnin_file_downloadable( @utf )
    @turnin = @utf.user_turnin 
    return unless turnin_for_assignment( @turnin, @assignment )
    
    line_number = params[:line]
    inst_comments = params[:comments]
    
    comment = FileComment.find(:first, :conditions => ["user_turnin_file_id=? and line_number=?", @utf.id, line_number] ) rescue comment = nil
    if comment.nil?
      comment = FileComment.new
    end
    comment.user_turnin_file = @utf
    comment.line_number = line_number
    comment.user = @user
    comment.comments = inst_comments
    
    comment.save
    @line = line_number
    render :layout => false
  end
  
  def toggle_style_item
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @utf = UserTurninFile.find( params[:id] )  
    return unless turnin_file_downloadable( @utf )
    @turnin = @utf.user_turnin 
    return unless turnin_for_assignment( @turnin, @assignment )
    
    line_number = params[:line]
    style_item = params[:file_style]
    
    style = FileStyle.find( style_item.to_i ) rescue comment = nil
    
    style.suppressed = !style.suppressed
    
    style.save
    
    @line = line_number
    
    @styles = FileStyle.find( :all, :conditions => ["user_turnin_file_id = ? and begin_line = ?", @utf.id, @line] )
    
    render :layout => false
  end
  
  def toggle_gradable_override
    throw "error" unless load_course( params[:course] )
    throw "error" unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    throw "error" unless assignment_in_course( @course, @assignment )
    
    @student = User.find( params[:student] )
    throw "error" unless student_in_course( @course, @student )
    
    @utf = UserTurninFile.find( params[:id] )  
    @turnin = @utf.user_turnin
    throw "error" unless turnin_file_downloadable( @utf )
    throw "error" unless turnin_for_assignment( @turnin, @assignment )
    
    @utf.gradable_override = ! @utf.gradable_override
    @utf.save
    
    
    render :layout => false
  end
  
  def view_io_tests
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @student = User.find( params[:student] )
    return unless student_in_course( @course, @student )
    
    # get turn-in sets
    @turnins = UserTurnin.find(:all, :conditions => ["user_id=? and assignment_id=?", @student.id, @assignment.id ], :order => "position DESC" )
    @current_turnin = @turnins[0] rescue @current_turnin = nil
    @display_turnin = @current_turnin
    return unless turnin_for_assignment( @current_turnin, @assignment )   
    
    # turnins
    @student_io_check = Hash.new
    @assignment.io_checks.each do |check|
       student_check = IoCheckResult.find(:first, :conditions => ["io_check_id = ? && user_turnin_id = ?", check.id, @current_turnin.id ] )
       unless student_check.nil?
         @student_io_check[check.id] = student_check
       end
    end
    
    render :layout => 'noright'
  end
  
  def io_retest
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @student = User.find( params[:student] )
    return unless student_in_course( @course, @student )
    
    # get turn-in sets
    @turnins = UserTurnin.find(:all, :conditions => ["user_id=? and assignment_id=?", @student.id, @assignment.id ], :order => "position DESC" )
    @current_turnin = @turnins[0] rescue @current_turnin = nil
    return unless turnin_for_assignment( @current_turnin, @assignment )   
    
    # submit for autograde
    queue = GradeQueue.new
    queue.user = @user
    queue.assignment = @assignment
    queue.user_turnin = @current_turnin
    if queue.save
      
      begin
        MiddleMan.schedule_worker(
          :class => :auto_grade_worker,
          :args => queue.id,
          :trigger_args => {
                :start => Time.now + 1.seconds
              }
        )
      rescue
        flash[:badnotice] = "The AutoGrade server wasn't running - but I've started it up and your grading will be begin shortl (may take up to 60 seconds)."
        ## bounce the server - the stop and then the start (stop has no effect if not running)
        `#{@app['ruby']} #{RAILS_ROOT}/script/backgroundrb stop`
        `#{@app['ruby']} #{RAILS_ROOT}/script/backgroundrb start`
      end
        
      ## need to do a different rediect
      redirect_to :controller => '/wait', :action => 'grade', :id => queue.id, :course => nil, :assignment => nil, :student => nil
      return
      
    else
      flash[:badnotice] = "There was an error submitting this assignment to the AutoGrade queue, please try again."
      redirect_to :course => @course, :assignment => @assignment, :student => @student, :action => 'view_io_tests'
    end
    
  end
  
  def view_file
    return unless load_course( params[:course] )
    return unless ensure_course_instructor_or_ta_with_setting( @course, @user, 'ta_view_student_files', 'ta_grade_individual' )
    
    @assignment = Assignment.find( @params[:assignment] )
    return unless assignment_in_course( @course, @assignment )
    
    @student = User.find( params[:student] )
    return unless student_in_course( @course, @student )
    
    @utf = UserTurninFile.find( params[:id] )  
    return unless turnin_file_downloadable( @utf )
    @turnin = @utf.user_turnin 
    return unless turnin_for_assignment( @turnin, @assignment )
    
    directory = @turnin.get_dir( @app['external_dir'] )
    
    # resolve file name
    relative_name = @utf.filename
    walker = @utf
    while walker.directory_parent > 0 
      walker = UserTurninFile.find( walker.directory_parent )
      relative_name = "#{walker.filename}/#{relative_name}"
    end
    
    # fix double slashes
    relative_name.gsub!(/\/\//,"/")
    filename = "#{directory}#{relative_name}"
    
    @title = "#{relative_name} - #{@student.display_name} (#{@student.uniqueid}) - #{@assignment.title}"
    
    begin      
      @lines = FileManager.format_file( @app['enscript_command'], filename, @utf.extension )
      
      if @utf.extension.eql?("java")
        @lines.each do |line| 
          public_index = line.index('public') 
          static_index = line.index('static') 
          void_index = line.index('void') 
          main_index = line.index('main') 
          #puts "p:#{public_index} s:#{static_index} v:#{void_index} m:#{main_index} line:#{line}"
          # line must contain all of these
          if( !public_index.nil? && !static_index.nil? && !void_index.nil? && !main_index.nil? &&
              static_index > public_index && void_index > public_index &&
              main_index > public_index && main_index > static_index && main_index > void_index )
            @java_main = true
            break
          end
        end
      end

      @comments = @utf.file_comments_hash
      @styles = @utf.file_style_hash( true )
      
    rescue
      flash[:badnotice] = "Error loading selected file.  Please contact your system administrator."
      redirect_to :action => 'view_student', :course => @course, :assignment => @assignment, :student => nil, :id => @student
      return
    end
    
    ## Execution interception
    if @java_main && params[:execute_java].eql?('true')
      absolute_directory = filename[0...filename.rindex('/')]
      base_file = filename[filename.rindex('/')+1..-1]
      
      @display_java_execute = true
      
      pl = ProgrammingLanguage.find_by_extension( @utf.extension )
      if pl.nil?
        flash[:badnotice] = "There was an error loading the programming language runtime for this language."
      else
        runner = SimpleProgramRunner.new( pl, absolute_directory, base_file, logger )
        @compile_out = runner.compile()
        @compile_success = runner.did_compile?()
        if @compile_success
          @command_line_arguments = params[:command_line_arguments]
          @standard_in = params[:standard_in]
          @execute_out = runner.execute( params[:command_line_arguments], params[:standard_in] )
          
          @execute_out_html = ""
          0.upto(@execute_out.size-1) do |i|
            str = @execute_out[i...i+1]
            if str.eql?("\n")
              @execute_out_html << "<br/>"
            elsif str.eql?(" ")
              @execute_out_html << "&nbsp;"
            else 
              @execute_out_html << str
            end
          end
        end
      end
    end
    
    render :layout => 'noright'
  end
  
  ## BEGIN PRIVATE UTILITY METHODS
  
  
  def set_tab
    @show_course_tabs = true
    @tab = "course_instructor"
  end
  
  def set_title
    @title = "Turins - #{@assignment.title}"
  end
  
  def assignment_in_course( course, assignment )
    unless course.id == assignment.course.id
      redirect_to :controller => '/instructor/index', :course => course
      flash[:notice] = "Requested assignment could not be found."
      return false
    end
    true
  end
  
  def turnin_for_assignment( turnin, assignment )
    unless turnin.assignment_id == assignment.id
      flash[:badnotice] = "The requested turn-in does not belong to this assignment."
      redirect_to :action => 'index', :assignment => assignment.id
    end
    true    
  end
  
  def turnin_file_downloadable( tif )
    if tif.directory_entry
      flash[:badnotice] = "Individual turn-in directories can not be downloaded"
      redirect_to :action => 'index', :assignment => tif.assignment_id
      return false
    end
    true
  end
  
  private :set_tab, :set_title, :assignment_in_course, :turnin_for_assignment, :turnin_file_downloadable
  
end
