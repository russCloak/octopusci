require 'active_record'

class Job < ActiveRecord::Base
  STATUS = {
    'pending' => 'Pending...',
    'running' => 'Running...',
    'successful' => 'Successful',
    'failed' => 'Failed',
    'error' => 'Error'
  }
  
  serialize :payload
  
  after_create :set_output_file_path
  
  def branch_name
    self.ref.gsub(/refs\/heads\//, '')
  end
  
  def display_status
    return STATUS[self.status]
  end
  
  def successful?
    return self.status == 'successful'
  end
  
  def failed?
    return self.status == 'failed'
  end
  
  def finished?
    return ['successful', 'failed', 'error'].include?(self.status)
  end 
  
  def output
    if File.exists?(self.abs_output_file_path)
      return File.open(self.abs_output_file_path, 'r').read()
    else
      return ""
    end
  end

  def silent_output
    if File.exists?(self.abs_silent_output_file_path)
      return File.open(self.abs_silent_output_file_path, 'r').read()
    else
      return ""
    end
  end
  
  def workspace_path
    return "#{Octopusci::CONFIG['general']['workspace_base_path']}/#{self.stage}"
  end
  
  # Relative path of the output file to the workspace base path.
  def rel_output_file_path
    "/jobs/#{self.id}/output.txt"
  end
  
  def abs_output_file_path
    return "#{Octopusci::CONFIG['general']['workspace_base_path']}#{self.rel_output_file_path}"
  end
  
  def abs_silent_output_file_path
    return "#{self.abs_output_path}/silent_output.txt"
  end
  
  def repository_path
    return "#{self.workspace_path}/#{self.repo_name}"
  end
  
  def abs_output_path
    return "#{Octopusci::CONFIG['general']['workspace_base_path']}/jobs/#{self.id}"
  end

  def code_cloned?
    return File.directory?(self.repository_path)
  end

  def clone_code(job_conf)
    if self.code_cloned?
      return 0
    else
      if !Dir.exists?(self.workspace_path)
        FileUtils.mkdir_p(self.workspace_path)
      end
      return self.run_command("cd #{self.workspace_path} 2>&1 && git clone #{job_conf['repo_uri']} #{self.repo_name} 2>&1", true)
    end
  end

  def checkout_branch(job_conf)
    if !self.code_cloned?
      self.clone_code(job_conf)
    end
    
    return self.run_command("cd #{self.repository_path} 2>&1 && git fetch --all -p 2>&1 && git checkout #{self.branch_name} 2>&1 && git pull -f origin #{self.branch_name}:#{self.branch_name} 2>&1", true)
  end
  
  # Runs a command and logs it standard output to the job's associated
  # output file. It also returns the exit status of the command that was
  # run as the integer exit status of the commands on the command line.
  def run_command(cmd_str, silently=false)
    # Make sure that the directory structure is in place for the job output.
    if !File.directory?(self.abs_output_path)
      FileUtils.mkdir_p(self.abs_output_path)
    end
    
    out_f = nil
    
    # Run the command and output the output to the job file
    if silently
      out_f = File.open(self.abs_silent_output_file_path, 'a')
    else
      out_f = File.open(self.abs_output_file_path, 'a')
    end
    out_f << "\n\nRunning: #{cmd_str}\n"
    out_f << "-"*30
    out_f << "\n"
    out_f.flush
    
    f = IO.popen(cmd_str)
    while(cur_line = f.gets) do
      out_f << cur_line
      out_f.flush
    end
    
    out_f.close
    f.close
    
    return $?.exitstatus.to_i
  end
  
  private
  
  def set_output_file_path
    self.output_file_path = self.rel_output_file_path()
    self.save!
  end
end