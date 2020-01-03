Dir.chdir __dir__
pinvoke_file = '../railapi/rail/sdk_csharp/internal_rail_api_pinvoke.cs'
text = File.read pinvoke_file
before1 = Regexp.escape '[global::System.Runtime.InteropServices.DllImport(dll_path,'
before2 = Regexp.escape 'EntryPoint="'
before3 = Regexp.escape '")]'
before4 = Regexp.escape 'public static extern '
regex = %r{#{before1}\s*#{before2}(\w+)#{before3}\s+#{before4}(\S+)\s+\w+\(\s*(.*?)\s*\);}m
puts <<~HEAD
using callback = void(**)(...); // callback_instance[0][0](args)
using string = void*;
using uint = unsigned int;
using ulong = unsigned int;
using byte = unsigned int;
using sbyte = unsigned int;
using ushort = unsigned int;
HEAD
text.scan(regex) do |name, ret, args|
  args = (args + ',').split.join(' ').gsub(/\[[^\]]+?\]/) { |a| a.include?('LPArray') ? 'LPArray ' : '' }
  args = args.scan(/\s*(.+?)\s*\w+,/).flatten.map { |a|
    next 'string[]' if a == 'LPArray string'
    next a.sub 'LPArray ', '' if a.start_with? 'LPArray '
    next a.strip
  }.map { |e|
    e = case e
    when /IntPtr/ then 'void*'
    when /RailResult/ then 'uint'
    when /^[A-Z]/ then 'callback'
    else e
    end
    if e.start_with? 'out '
      e[4..-1].strip
    else
      next e
    end
  }
  ret = case ret
  when /IntPtr/ then 'void*'
  else ret
  end
  puts "#{ret} #{name}(#{args.join(', ')});"
end
