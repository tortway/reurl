require 'rubygems'
require 'sqlite3'
require 'json'
class To_SQLite3
  def initialize(file_db='titles.db')
    @db=SQLite3::Database.open file_db
    @name=nil
    @columns='*'
    @where=Hash.new
    @query_list=String.new
    @order=String.new
    @with=Hash.new
    @limit=Array.new
    #@manual=false
  end
  attr_reader :name, :columns, :where, :query_list, :order, :with, :limit
  #def manual=value
  #  @manual=case
  #            when value.class.equal?(String) then value=='true'?true:false
  #            else false
  #          end
  #end
  def name=value
    @name=value.to_s
  end
  def table=value
    clear
    self.name=value
  end
  def columns=value
    @columns=value
  end
  def where=value
    @where=case
             when value.nil? then Hash.new
             when value.class.equal?(Array) then Hash[*value]
             else value
           end
  end
  def order=value
    @order=case
             when value.nil?||value.empty? then :id
             else value
           end
  end
  def with=value
    @with=value
  end
  def limit=value
    @limit=value
  end

  def do_query(query) #=false
    if query.equal?(true)#||@manual
      @db.execute_batch(@query_list)
      @query_list=String.new
      #@manual=false
    else
      begin
        puts query
        @db.execute query
      rescue SQLite3::Exception => e
	puts e
        sleep(10)
        retry
      end
    end
  end
  def hold_query query
    @query_list<<"#{query};"
  end

  #def form_where
  #  query=String.new
  #  or_and='AND'
  #  unless @where.empty?
  #    pairs=@where.map do |a|
  #      if a[0]==:is_or&&a[1]
  #        or_and='OR'
  #        next
  #      end
  #      a[1].class.equal?(Array) ? "#{a[0]} IN('#{a[1].join("','")}')":"#{a[0]}='#{a[1]}'"
  #    end
  #    query<<" WHERE #{pairs.shift}"
  #    pairs.each{|e| query<<" #{or_and} #{e}"} if pairs[0]
  #  end
  #  query
  #end

  def form_where
    query=String.new
    unless @where.empty?
      query=" WHERE #{cv_rows(@where, ' AND ')}"
    end
    query
  end

  def form_order
    query=String.new
    unless @order.empty?
      order_type=:order
      if @order.class.equal?(Array)
        order_type=@order[1].nil? ? :order : @order[1]
        value=@order[0].to_s
        unless @order[2].nil?
          value+=" order by #{@order[0]}" if order_type==:group
          value+=" #{@order[2]}"
        end
      else
        value=@order
      end
      query << " #{order_type} by " << value
    end
    query
  end

  def form_with
    query=String.new
    unless @with.empty?
      @with.each do |column,value|
        query << " INNER JOIN #{column} ON "
        query << cv_rows(value, ' AND ')
      end
    end
    query
  end

  def form_limit
    query=String.new
    unless limit.empty?
      query=" LIMIT #{limit[0]},#{limit[1]}"

    end
    query
  end

  # добавить к методу take принятие массива символов необходимых для создания хеша на выходе:
  # old_data=[[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5]]
  # keys=[:a,:b,:c]
  # values.insert(2,keys)
  # values.insert(1,keys)
  # values.insert(0,keys)
  # data=[]
  # data<<Hash[*values[0..1].transpose.flatten]
  # data<<Hash[*values[2..3].transpose.flatten]
  # data<<Hash[*values[4..5].transpose.flatten]
  def take(improved=false) # будет принимать хеш, либо просто true, и тогда он сам возьмет хеш от columns
    @columns='*' if !@columns||@columns==''
    query=if @columns.class.equal?(Array)
            c_row=String.new
            @columns.each { |v| c_row<<"#{v}," }
            "SELECT #{c_row[0..-2]} FROM `#{@name}`"
          elsif @columns.class.equal?(String||Symbol)
            "SELECT #{@columns} FROM `#{@name}`"
          end
    return nil if query.nil?

    data=do_query query<<form_with<<form_where<<form_order<<form_limit
    if improved
      improved_data=Array.new
      data.each_with_index do |value, index|
        value.each_with_index {|v, i|(improved_data[index]||={}).merge!(columns[i] => v)}
      end
      improved_data
    else data
    end
  end

  def first(improved=false)
    data=take[0]
    if data
      if improved
        improved_data=Hash.new
        data.each_with_index{|v, i|improved_data[columns[i]]=v}
        improved_data
      else data[0]
      end
    end
  end

  def view default=false
    data=take
    return 'Error: nothing for view' if data.nil?
    if default
      data.each do |row|
        puts row.to_s
      end
    else
      data.each do |row|
        yield(row)
      end
    end
  end

  def add do_not_execute=false
    return 'Error: cannot add' unless @columns.class.equal?(Hash)
    query="INSERT INTO #{name}(#{cv_rows(@columns.keys)}) VALUES(#{cv_rows(@columns.values)})"

    if do_not_execute
      hold_query query
    else
      do_query query
    end
  end

  def get_last_id
    (do_query 'SELECT last_insert_rowid()')[0][0]
  end

  def do_not
    yield
  end

  def change do_not_execute=false
    @columns=Hash[*@columns] if @columns.class.equal?(Array)
    query="UPDATE `#{name}` SET #{cv_rows(@columns,', ')}"+form_where

    if do_not_execute
      hold_query query
    else
      do_query query
    end
  end

  def remove do_not_execute=false
    query="DELETE FROM `#{name}`"+form_where

    #@manual?(hold_query query):(do_query query)
    if do_not_execute
      hold_query query
    else
      do_query query
    end
  end

  def amount
    query="SELECT COUNT(*) FROM #{name}"+form_with+form_where
    (do_query query)[0][0]
  end

  def clear(save_table_name=false)
    @name=nil unless save_table_name
    @columns='*'
    @where=Hash.new
    @order=Hash.new
    @with=Hash.new
    @query_list=String.new
    @limit=Array.new
  end

  def cv_rows(cv, separator=',', operation='=', func='IN')
    rows=String.new
    if cv.class.eql?(Array)
      cv.each{|e| rows << ([Symbol, Fixnum, Bignum].include?(e.class)? "#{e}#{separator}" : "'#{cut(e)}'#{separator}")}
      rows[0..-(separator.length+1)]
    elsif cv.class.eql?(Hash)
      cv.each_with_index do |(column, value), index|
        rows << separator if index>0
        if value.class.equal?(Array)
          if column.class.equal?(Hash)
            func=column.delete(:func)
            sub_separator=column.delete(:separator)||','
            column=''
          else
            sub_separator=','
          end
          rows << "#{column} #{func}(#{cv_rows(value,sub_separator)})"
        elsif value.class.equal?(Hash)
          if column.class.equal?(Hash)
            sub_separator=column.delete(:separator)||:AND
            sub_operation=column.delete(:operation)||'='
          else
            sub_separator=column
            sub_operation='='
          end
          rows << "(#{cv_rows(value, " #{sub_separator} ", sub_operation)})"
        else
          column,value=[column,value].map{|e| [Symbol, Fixnum, Bignum].include?(e.class)? e:"'#{cut(e)}'"}
          rows << "#{column}#{operation}#{value}"
        end
      end
      rows
    else nil
    end
  end
  def cut(value)
    if value.class.equal? String
      value.gsub("'",'&prime;').gsub('"','&quot;').gsub(/[~\^<>\{\}\*]/,'')
    else value
    end
  end
end
