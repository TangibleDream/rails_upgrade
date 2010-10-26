$:.unshift(File.dirname(__FILE__) + "/../../lib")
require 'converter_base'
require 'arel_converter'

module Rails
  module Converter
    class ActiveRecordFinder < Base
      
      def run
        Dir['app/**/*'].each do |file|
          begin
            parse_file(file) unless File.directory?(file)
          rescue => e
            alert(file, [], e.message)
          end
        end
      end

      def parse_file(file)
        raw_ar_finders = ''
        ["find(:all", "find(:first", "find.*:conditions =>", ":joins =>"].each do |v|
          raw_ar_finders += `grep -r '#{v}' #{file}`
        end
        ar_finders = raw_ar_finders.split("\n").uniq.reject {|l| l.include?('named_scope') }
        
        unless ar_finders.empty?

          failures = []
          
          new_ar_finders = ar_finders.map do |ar_finder|
            begin
              full_method, arguments = find_method(ar_finder)
              case full_method
              when nil
                raise RuntimeError, "can't parse due to unmatched braces"
              when 'find(:all)'
                new_line = ar_finder.sub(full_method, 'all')
              when 'find(:first)'
                new_line = ar_finder.sub(full_method, 'first')
              else
                finder_hash = arguments.split(',')
                all_or_first = finder_hash.shift
                sexp = ParseTree.new.process("{#{finder_hash.join(',')}}")
                arel = ArelConverter.new.process(sexp)
                new_line = ar_finder.sub(full_method, arel)
                new_line += ".first" if all_or_first.include?(':first')
              end
              [ar_finder,new_line]
            rescue SyntaxError => e
              failures << "SyntaxError when evaluatiing options for #{ar_finder}"
              nil
            rescue => e
              failures << "#{e.class} #{e.message} when evaluatiing options for #{ar_finder}\n#{e.backtrace.first}"
              nil
            end
          end.compact
          alert(file, new_ar_finders, failures) unless (new_ar_finders.nil? || new_ar_finders.empty?) && failures.empty?
        end
      end
      
    protected
    
      def find_method(line)
        i = line.index('find')
        braces = 0
        full_method = ''
        args = ''

        while i < line.length
          char = line[i].chr
          full_method << char
          args << char if braces > 0
          case char
          when '('
            braces += 1
          when ')'
            braces -= 1
            if braces == 0
              args.chop!
              break 
            end
          end
          i += 1
        end
        braces == 0 ? [full_method, args] : [nil,nil]
      end
    end
  end
end