# encoding: UTF-8
require 'rack'	
require 'sinatra'
require 'sinatra/base'
require 'sinatra/param'
require 'sinatra/contrib'
#require 'sinatra/content_for'
require 'sinatra/synchrony'
require 'thin'
require 'sinatra/config_file'
require 'sinatra/json'
require 'sinatra/flash'
require 'sinatra/captcha'
require 'rack/throttle'
require 'rack/protection'
require 'rack/attack'

require 'haml'
require 'json'
require 'digest/md5'
require 'date'
require 'base64'
require 'ipaddr'
require 'geoip'
require 'jsobfu'

require 'unicode'
class String
  def downcase
    Unicode::downcase(self)
  end
  def downcase!
    self.replace downcase
  end
  def upcase
    Unicode::upcase(self)
  end
  def upcase!
    self.replace upcase
  end
  def capitalize
    Unicode::capitalize(self)
  end
  def capitalize!
    self.replace capitalize
  end
end

require_relative 'to_SQLite3'
require_relative 'parse_do'
require_relative 'reurl_error'

config_file 'config.yml'
#set :bind, '192.168.0.214'
set :server, 'thin'
set :port, 4567
set :haml, {format: :html5, attr_wrapper: '"'}
#set :show_exceptions, false
#set :raise_sinatra_param_exceptions, true

#1enable :sessions

#use Rack::Throttle::Minute, max: 120
#use Rack::Throttle::Hourly, max: 4000

#use Rack::Attack
#
#Rack::Attack.blacklisted_response = lambda do |env|
#  [ 503, {}, ['Blocked. Your ip has been sent to FBI.']]
#end
#Rack::Attack.blacklist('block ip\'s') do |req|
#  [].include? req.ip
#end


db=To_SQLite3.new('fl.db')
geoip=GeoIP.new('GeoIP.dat')

error Sinatra::Param::InvalidParameterError do
  flash.next[:err]=env['sinatra.error'].param
  redirect back
end
error ReurlError do
  flash.next[:err]=env['sinatra.error'].message
  redirect back
end

def authorized?
  @auth ||=  Rack::Auth::Basic::Request.new(request.env)
  @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == %w(tortway Satistite123)
end
def protected!
  unless authorized?
    response['WWW-Authenticate'] = 'Basic realm="Запретная зона"'
    throw(:halt, [401, 'Запретная зона'])
  end
end

helpers do
  def md5(value)
    Digest::MD5.hexdigest(value)
  end
  def i_to_ip(integer)
    IPAddr.new(integer,Socket::AF_INET)
  end
  def ip_to_i(ip)
    IPAddr.new(ip).to_i
  end

  def rand_m(m, mids)
    ind=nil
    loop do
      break if m.size<=0
      ind=rand(m.size)
      if mids && mids.include?(m[ind][:mid])
        m.delete_at(ind)
        ind=nil
        next
      end
      if rand(100)<=m[ind][:ratio]
        break
      else
        m.delete_at(ind)
        ind=nil
      end
    end
    ind ? m[ind]:nil
  end

  def kw_setup(keywords, amounting=true)
    help_db=To_SQLite3.new('fl.db')
    kw=Hash.new
    keywords.gsub(',', ' ').split.each{|e| kw[e[0..-2]]=e}
    help_db.table=:k
    help_db.columns=[:pre_keyword]
    pre_kw_from_db=help_db.take
    kw.each do |pre_keyword, keyword|
      if pre_kw_from_db.include? pre_keyword
        if amounting
          help_db.columns={amount: :'amount+1'}
          help_db.where={pre_keyword: pre_keyword}
          help_db.change
        end
      else
        help_db.columns={keyword: keyword, pre_keyword: pre_keyword}
        help_db.add
      end
    end
  end
end

#get '/:qwe' do haml :work, layout: false end

get '/new' do 
  redirect '/' 
end
get '/unknown' do haml :unknown end
get '/error/:name' do |name| json({error: name}, :encoder => :to_json, :content_type => :js) end
get '/' do
  param :r, Integer
  if params[:r]
    response.set_cookie(:r, value: params[:r])
  end

  redirect cookies[:a]? '/my':'/about'
end

get '/about' do
  @page='about'

  db.table=:a
  db.columns=[:lgn, :'cast(paydone as number) as top']
  db.where={{operation: '<>'} => {paydone: 0}}
  db.order=[:top, :order, :desc]
  db.limit=[0, 5]
  @top=db.take true

  @err={
      url:'Неправильный формат ссылки! Пожалуйста, убедитесь, что в ссылке присутствует имя и домен',
      timeout: 'Запрашиваемый сайт не доступен, попробуйте позже',
      fatal: 'Запрашиваемый сайт выдал ошибку, попробуйте позже'
  }
  haml :about
end

get '/stats' do
  db.table=:c
  db.columns=[:country, :'count(*)']
  db.with={i: {:'i.ipid' => :'c.ipid'}}
  db.order=[:country, :group, :desc]
  @geo=db.take

  db.table=:c
  @total=db.amount

  haml :stats
end

get '/api' do
  @apihash=cookies[:a]
  haml :api
end

post '/new' do
  begin
    param :url, String, required: true, format: /.\..{2,}/
    param :tmp, String, format: /^.{32}$/
    param :tmp_new, Integer, default: 0
    param :file, Integer, default: 0
    param :title, String
    param :description, String
    param :keywords, String
  rescue Sinatra::Param::InvalidParameterError => err
    if params[:tmp]
      redirect "/error/#{err.param}"
      json({error: err.param}, :encoder => :to_json, :content_type => :js)
    else raise ReurlError, 'url'
    end
  end

  tmp=cookies[:a]
  db.table=:a
  if tmp||=params[:tmp]
    db.columns=[:accid]
    db.where={tmp: tmp}
    accid=db.first
  else accid=nil
  end

  if accid.nil? && params[:tmp].nil?
    tmp=md5(Time.now.to_i.to_s(36)+Random.new_seed.to_s(36))
    db.columns={tmp: tmp}
    if cookies[:r]&&cookies[:r]=~/^\d+$/
      db.columns[:refid]=cookies[:r].to_i
      response.delete_cookie 'r'
    end
    db.add
    accid=db.get_last_id

    response.set_cookie(:a, value: tmp, expires: Time.gm(2038,1,19,3,14,8))
    response.set_cookie(:id, value: accid, expires: Time.gm(2038,1,19,3,14,8))
  elsif accid.nil?
    redirect '/error/tmp' if params[:tmp]
    return 'tmp'
  end

  db.table=:u
  if params[:file]==1
    url=params[:url]
    title=params[:title]
    url.scan(/^.+\/(.+?)$/){|v| title=v[0]} unless title
    title||='install'
    db.columns={accid: accid, url: params[:url], title: title, keywords: 'direct_link_to_file', file: 1}
  else
    parsedo=ParseDo.new # тут могут быть ошибки, которые класс не возвращает
    parsedo.get=params[:url]
    metas=parsedo.parse

    db.columns={accid: accid, url: parsedo.url, xfo: parsedo.xfo}
    if params[:tmp]
      db.columns[:title]=params[:title]
      db.columns[:description]=params[:description]
      keywords=params[:keywords]
      unless keywords.nil?
        keywords.downcase!
        kw_setup(keywords) # чо не работае га?
      end
      db.columns[:keywords]=keywords
    end

    metas.compact.each do |e|
      if params[:tmp].nil? || ( params[:tmp] && params[e[0]].nil? )
        db.columns[e[0].to_sym]=e[1].gsub("'",'&rsquo;') if %w(description keywords title).include?(e[0])&&!e[1].nil?
      end
    end
    @metas=Hash.new
    {title: 'Заголовок', description: 'Описание', keywords: 'Ключевые слова'}.
        each{|k,v| @metas[k]={label: v, content: db.columns[k]}}
  end
  db.add
  @urlid=db.get_last_id

  @url="#{request.base_url}/#{@urlid.to_s(36)}"

  if params[:tmp] || params[:tmp_new]==1
    json({url: @url, id: @urlid}, :encoder => :to_json, :content_type => :js)
  else
    haml :new
  end
end

get '/regauth' do
  if cookies[:a]
    db.table=:a
    db.columns=[:accid,:psw]
    db.where={tmp: cookies[:a]}
    @acc_data=db.first true
  end

  @page='regauth'
  @err={
      bad_auth: 'Неверное имя или пароль',
      user_exist: 'Пользователь с таким именем уже существует',
      lgn: 'Необходимо ввести имя (от 1 до 20 символов)',
      psw: 'Необходимо ввести пароль (от 5 символов)',
      captcha: 'Неверно введен код на картинке'
  }
  haml @acc_data&&@acc_data[:psw]? :unknown : :regauth
end

post '/regauth' do
  raise ReurlError, 'captcha' unless captcha_pass?

  param :lgn, String, required: true, min_length:1, max_length:20
  param :psw, String, required: true, min_length:5
  param :reg, String
  param :auth, String
  one_of :reg, :auth

  db.table=:a
  tmp=nil
  if params[:reg]
    db.where=[lgn: params[:lgn]]
    if db.amount<=0
      psw_hash=md5("#{params[:lgn]}#{params[:psw]}yuj11ewg49hb")
      db.columns={
          lgn: params[:lgn],
          psw: psw_hash,
      }
      if cookies[:r]&&cookies[:r]=~/^\d+$/
        db.columns[:refid]=cookies[:r].to_i
        response.delete_cookie 'r'
      end
      if cookies[:a]
        db.where={tmp: cookies[:a]}
        db.change
      else
        db.columns[:tmp]=tmp=md5(Time.now.to_i.to_s(36)+Random.new_seed.to_s(36))
        db.add
      end
    else raise ReurlError, 'user_exist'
    end
  else
    psw_hash=md5("#{params[:lgn]}#{params[:psw]}yuj11ewg49hb")
    db.columns=[:tmp,:accid]
    db.where={lgn: params[:lgn], psw: psw_hash}
    acc=db.first true
    raise ReurlError, 'bad_auth' unless acc

    tmp=acc[:tmp]
    if cookies[:a]&&tmp
      db.columns=[:accid]
      db.where={tmp: cookies[:a]}
      old_accid=db.first
      db.remove
      db.table=:u
      db.columns={accid: acc[:accid]}
      db.where={accid: old_accid}
      db.change
    end
  end
  response.delete_cookie 'id'
  response.set_cookie(:lgn, value: params[:lgn], expires: Time.gm(2038,1,19,3,14,8))
  response.set_cookie(:a, value: tmp, expires: Time.gm(2038,1,19,3,14,8)) if tmp
  redirect '/'
end

get '/my' do
  @urls_data=@files_data=@all_data=Array.new
  if cookies[:a]
    params[:by]=:time unless [:time, :uniques, :clicks, :title].include?((params[:by]||=:time).to_sym)
    @by=params[:by].to_sym

    db.table=:u
    db.columns=[:id, :title, :url, :hidden, :description, :keywords, :time, :clicks, :uniques, :unidone, :funidone, :paydone, :lasttime, :file]
    db.with={a: {:'a.accid' => :'u.accid'}}
    db.where={tmp: cookies[:a]}
    db.order=[params[:by], :order, params[:on]||=:desc]
    @all_data=result_data=db.take true

    @urls_data=result_data.select{|key, hash| key[:file] == 0}
    @files_data=result_data.select{|key, hash| key[:file] == 1}
  end

  if result_data && !result_data.empty?
    @uniques=@urls_data.empty? ? 0:@urls_data.inject(0){|sum,hash| sum+hash[:uniques]}
    @f_uniques=@files_data.empty? ? 0:@files_data.inject(0){|sum,hash| sum+hash[:uniques]}

    @clicks=result_data.inject(0){|sum,hash| sum+hash[:clicks]}
    unidone=result_data[0][:unidone]
    f_unidone=result_data[0][:funidone]
    @already=result_data[0][:paydone]
  else
    @clicks=unidone=@uniques=@f_uniques=f_unidone=@already=0
  end

  db.table=:t
  db.columns=[:salary, :fsalary]
  @sal=db.first true

  @done=(((@uniques-unidone)*@sal[:salary].to_f)+
      ((@f_uniques-f_unidone)*@sal[:fsalary].to_f)+@already.to_f||=0).round(2)

  @page='my'
  @err={
      url:'Неправильный формат ссылки! Пожалуйста, убедитесь, что в ссылке присутствует имя и домен',
      timeout: 'Запрашиваемый сайт не доступен, попробуйте позже',
      fatal: 'Запрашиваемый сайт выдал ошибку, попробуйте позже'
  }
  haml :urllist
end

post '/do/:type/:id' do |type,id|
  begin
    param :url, String, format: /.\..{2,}/
    param :type, String, in: %w(delete save)
    param :id, Integer, required: true

    param :tmp, String, format: /^.{32}$/

    any_of :url, :type
  rescue Sinatra::Param::InvalidParameterError => err # без этого ajax не получит сообщение об ошибке
    return err.param
  end

  conditions={:'u.accid' => :'a.accid', tmp: cookies[:a]||params[:tmp]}
  return 'tmp' if conditions[:tmp].nil?

  db.table=:u
  db.columns=[:id]
  db.with={a: conditions}
  db.where={id: id}
  a=db.amount
  if a>0
    if type.eql? 'delete'
      db.columns={hidden:1, description: nil, keywords: nil, title: nil}
      db.change
      return 'good' if params[:tmp]
      redirect params[:to] if params[:to]
    elsif type.eql? 'save'
      params[:url].insert(0,'http://') unless params[:url].nil?||params[:url]=~/^.{4,5}:\/\//
      unless params[:keywords].nil?
        params[:keywords].downcase!
        kw_setup(params[:keywords], false)
      end

      db.columns=params.select{|key, value| [:keywords, :description, :title, :url].include? key.to_sym}
      db.change
      return 'good' if params[:tmp]
    else 'type'
    end
  else 'err'
  end
end

get '/acc' do
  # тут будут настройки аккаунта, типа пароль, кошельки, а также выводиться accid
  # потом сделаю еще необязательный email, для возможности восстановить пароль
end

get '/conf' do
  # тут будут различные настройки, типа цветосхема "страницы с переходом" и т.п.
end

get '/quit' do
  response.delete_cookie 'id'
  response.delete_cookie 'lgn'
  response.delete_cookie 'a'
  redirect '/'
end

get '/money' do
  @page='money'
  @already=@can_be=@done=0

  if cookies[:a]
    db.table=:o
    db.with={a: {:'o.accid' => :'a.accid', :'a.tmp' => cookies[:a]}}
    @bid=db.amount>0

    unless @bid
      db.table=:a
      db.columns=[:qiwi, :webmoney, :yandex]
      db.where={tmp: cookies[:a]}
      @money=db.first true
    end

    db.table=:u
    db.columns=[:file, :uniques, :unidone, :funidone, :paydone]
    db.with={a: {:'a.accid' => :'u.accid'}}
    db.where={tmp: cookies[:a]}
    res_uni=db.take true

    if res_uni && !res_uni.empty?
      db.table=:t
      db.columns=[:salary, :fsalary]
      sal=db.first true

      uni=res_uni.select{|key, hash| key[:file] == 0}
      funi=res_uni.select{|key, hash| key[:file] == 1}

      uniques=uni.empty? ? 0:uni.inject(0){|sum,hash| sum+hash[:uniques]}
      f_uniques=funi.empty? ? 0:funi.inject(0){|sum,hash| sum+hash[:uniques]}
      unidone=res_uni[0][:unidone]
      f_unidone=res_uni[0][:funidone]
      @already=res_uni[0][:paydone]

      @can_be=((uniques-unidone)*sal[:salary].to_f+
          (f_uniques-f_unidone)*sal[:fsalary].to_f).round(2)
      @done=(@can_be+@already.to_f||=0).round(2)
    end
  end

  @err={money: 'Чтобы вывести деньги, вы должны ввести как минимум 1 кошелек'}
  haml :money
end
post '/money' do
  param :qiwi, String
  param :webmoney, String
  param :yandex, String
  begin
    any_of :qiwi, :webmoney, :yandex
  rescue Sinatra::Param::InvalidParameterError => err
    raise ReurlError, 'money'
  end

  db.table=:a
  db.columns=params.select{|key,value| [:qiwi,:webmoney,:yandex].include? key.to_sym}
  db.where={tmp: cookies[:a]}
  db.change

  db.name=:a
  db.columns=[:accid]
  accid=db.first

  db.table=:o
  db.columns={accid: accid}
  db.add

  redirect '/money'
end

get '/admin' do
  protected!
  params[:by]||=:mid
  db.table=:m
  db.columns=[:mid, :name, :target, :pay, :ratio, :stop, :geo, :keywords, :uniques, :sum]
  db.order=[params[:by], :order, :desc]
  @mon=db.take true

  db.table=:c
  db.columns=[:mid, :'count(*)']
  db.order=[:mid, :group]
  counts=db.take.flatten

  @uniques=Hash[*counts]
  db.table=:t
  db.columns=[:salary, :fsalary, :missedto]
  @tuning=db.first true

  @total_g=@total_t=0

  @err={
      name: 'Нужно ввести название',
      target: 'Нужно ввести рекламную ссылку',
      pay: 'Нужно ввести сумму, которую платит рекламодатель за уника',
      ratio: 'Нужно ввести процент вероятности показа рекламы',
      stop: 'Нужно ввести количество уников, которое покупает рекламодатель',
      salary: 'Нужно ввести сумму, которую вы будете отдавать владельцам ссылок за каждого уника'
  }
  haml :admin
end
post '/admin' do
  protected!
  param :name, String, required: true, format: /^.{2,}$/
  param :target, String, required: true, format: /.\..{2,}/
  param :pay, Float, required: true
  param :ratio, Integer, default: 100
  param :stop, Integer
  param :geo, String
  param :keywords, String

  db.table=:m
  db.columns=params.select{|key,value| [:name, :target, :pay, :ratio, :stop, :geo, :keywords].include? key.to_sym}
  db.add

  redirect '/admin'
end
post '/admin/config' do
  protected!
  param :salary, String, format: /^[\d\.]+$/
  param :fsalary, String, format: /^[\d\.]+$/
  param :missedto, String, format: /^.+$/

  db.table=:t
  db.columns=params.select{|key,value| [:salary, :fsalary, :missedto].include? key.to_sym}
  db.change

  redirect '/admin'
end
get '/admin/delete/:mid' do
  protected!
  param :mid, Integer, required: true

  db.table=:m
  db.where={mid: params[:mid]}
  db.remove
  db.name=:m
  db.remove

  redirect '/admin'
end
get '/admin/cashout' do
  protected!
  db.table=:o
  db.columns=[:'o.accid', :lgn, :qiwi, :webmoney, :yandex]
  db.with={a: {:'o.accid' => :'a.accid'}}
  @cashout=db.take true

  db.table=:u
  db.columns=[:'u.accid', :file, :clicks, :uniques, :unidone, :funidone]
  db.with={a: {:'a.accid' => :'u.accid'}}
  db.where={:'u.accid' => @cashout.map{|hash| hash[:'o.accid']}}
  @result_data=db.take true

  db.table=:r
  db.columns=[:accid, :ref, :'count(ref)']
  db.order=[:ref, :group, :asc]
  @ref_data=db.take true

  db.table=:t
  db.columns=[:salary, :fsalary]
  @sal=db.first true

  haml :cashout
end
post '/admin/cashout' do
  protected!
  param :accid, Integer, required: true
  param :new_unidone, Integer, required: true
  param :new_funidone, Integer, required: true
  param :cancel, String
  param :done, String
  one_of :cancel, :done

  if params[:done]
    db.table=:t
    db.columns=[:salary, :fsalary, :paydone]
    db.with={a: {accid: params[:accid]}}
    data=db.first true

    db.table=:a
    db.columns={
        unidone: :"unidone+#{params[:new_unidone]}",
        funidone: :"funidone+#{params[:new_funidone]}",
        paydone: (data[:paydone].to_f+
            (params[:new_unidone]||=0)*data[:salary].to_f+
            (params[:new_funidone]||=0)*data[:fsalary].to_f).round(2)
    }
    db.where={accid: params[:accid]}
    db.change

    db.name=:r
    db.remove
  end
  db.table=:o
  db.where={accid: params[:accid]}
  db.remove

  redirect '/admin/cashout'
end

get '/convert/:secret/:sum/:mid' do |secret, sum, mid|
  redirect '/unknown' if secret!='satiqwe'

  db.table=:m
  db.columns=[:sum]
  db.where={mid: mid}
  total=db.first
  db.columns={sum: (total.to_f+sum.to_f).round(2)}
  db.change
end

get '/catalog' do
  @qwe=params[:item]
  if @qwe
    @qwe.gsub!(/[<>'"]/, '')
    db.table=:u
    db.columns=[:id, :title]
    db.where={{operation: ' like '} => {:keywords => "%#{@qwe[0..-2].downcase}_%"}}
    db.order=[:id, :order, :desc]
    @list=db.take true
  end
  haml :catalog
end

get '/:hashid' do |hashid|
  # Итог: чтобы производилась накрутка, боты должны каждый раз менять дату либо чистить l.storage и флеш куку,
  # либо, они должны каждый раз парсить и совершать деобфускацию, чтобы получить нужные хеши для создания уника.
  # и обхойти таким образом проверки, связавшись с сервером напрямую.

  # Так, еще надо улучшить подбор партнерки, т.е. добавить поиск по ключевым словам ссылки и стране уника

  hash=md5(hashid+'4ipo43as6tiu')
  id=hashid.to_i(36)
  db.table=:u
  db.columns=[:accid, :url, :title, :description, :keywords, :xfo, :clicks, :uniques, :hidden, :file]
  db.where={id: id}
  url_data=db.first true

  redirect '/unknown' if url_data.nil?
  redirect url_data[:url] if url_data[:hidden]==1

  db.table=:i
  db.columns=[:ipid, :ref]
  db.where={ip: ip_to_i(request.ip)}
  ires=db.first true
  ipid=ires[:ipid] if ires
  unless ipid
    db.columns={ip: ip_to_i(request.ip), country: geoip.country(request.ip)[5], ref: request.referer, ua: request.user_agent}
    db.add
    ipid=db.get_last_id
  end

  db.table=:m
  db.columns=[:mid, :target, :ratio, :'m.uniques', :name]

  if cookies[:h]&&cookies[:h]==hash && cookies[:m]
    response.delete_cookie 'h'
    m=db.take true

    mid=nil
    mobject=Hash.new
    m.each_with_index do |hash, index|
      if md5("w9v34#{mid=hash[:mid]}#{request.ip}p3y[d")==cookies[:m]
        mobject=m[index]
        break
      end
      mid=nil
    end
    response.delete_cookie 'm'
    db.table=:u
    db.columns={clicks: :'clicks+1', lasttime: Date.today.strftime('%Y-%m-%d 00:00:00')}
    db.where={id: id}
    db.change

    db.table=:c
    db.where={ipid: ipid, mid: mid}
    if mid && db.amount <= 0
      time_is=md5("#{mid}#{Date.today.strftime('%Y-%m-%d')}")
      source=%Q|
        localStorage.setItem('#{time_is}', '1');
        var mySwfStore = new SwfStore({
          namespace: 'reurl',
          swf_url: 'http://reurl.ru/js/reurl.swf',
          debug: true,
          onready: function(){
            mySwfStore.set('#{time_is}', '1');
          },
          onerror: function(){
            //qwe
          }
        });
      |

      db.name=:c
      db.columns={ipid: ipid, mid: mid}
      db.add

      db.table=:m
      db.columns={uniques: :'uniques+1'}
      db.where={mid: mid}
      db.change

      db.name=:u
      db.where={id: id}
      db.change

      db.table=:r
      db.columns={accid: url_data[:accid], ref: ires[:ref]}
      db.add
    end

    if url_data[:xfo]==1
      source||=String.new
      source << "window.location.href='#{url_data[:url]}';"
      @js=JSObfu.new(source).obfuscate(iterations: 2)
      haml :redirect, layout: false
    else
      @js=JSObfu.new(source||='//qwe').obfuscate(iterations: 2)
      if url_data[:file]!=1 || mid.nil?
        @target=url_data[:url]
      else
        @target=mobject[:target].
            gsub('reurl_name', url_data[:title]).
            gsub('reurl_url', url_data[:url])
      end
      @title=url_data[:title]
      haml :finish, layout: false
    end
  else
    db.with={i: {ipid: ipid}, u: {id: id}}
    db.where={
        OR: {{operation: '<'} => {:'m.uniques' => :'stop'}, stop: 0},
        or: {geo: '', {func: 'instr'} => [:geo, :country]},
    }
    if url_data[:keywords].nil? || url_data[:keywords].empty?
      db.where[:'m.keywords']=''
    elsif url_data[:keywords]
      keywords=Array.new
      url_data[:keywords].gsub("'",' ').split.each{|e| keywords << :"instr(m.keywords,'#{e.downcase}')"}

      db.where[:oR]={
          AND: {:'u.file' => 1, {func: 'instr'} => [:'m.keywords','direct_link_to_file']},
          and: {:'u.file' => 0, OR: {:'m.keywords' => '', {func: '', separator: ' OR '} => keywords}}
        }
    else db.where[:'m.keywords']=''
    end
    m=db.take true

    response.delete_cookie 'm'
    db.table=:c
    db.columns=[:mid]
    db.where={ipid: ipid}
    mids=db.take.transpose[0]

    db.table=:t
    db.columns=[:missedto]
    alt_target=missedto=db.first

    if (result_m=rand_m(m, mids)).nil?
      target=missedto
    else
      mid_hash=md5("w9v34#{result_m[:mid]}#{request.ip}p3y[d")
      target=result_m[:target]
    end

    if url_data[:file]==1
      target=hashid
      alt_target=url_data[:url]
    end
    time_is=md5("#{result_m[:mid]}#{Date.today.strftime('%Y-%m-%d')}") unless result_m.nil?

    source=%Q|
        document.cookie="h=#{hash}";
        var target="#{target}"
        var m="#{mid_hash}";
    |
    if mid_hash
      source<<%Q|
        if(m != ''){
          if(typeof(Storage) !== "undefined") {
            if(localStorage.getItem('#{time_is}')){
              m='';
              target='#{alt_target}';
            }
          }else {
            //пока без альтернатив
          }
          var mySwfStore = new SwfStore({
            namespace: 'reurl',
            swf_url: 'http://reurl.ru/js/reurl.swf',
            debug: true,
            onready: function(){
              if(mySwfStore.get('#{time_is}')=='1'){
                m='';
                target='#{alt_target}';
              }
            },
            onerror: function(){
              //qwe
            }
          });
        }
      |

      db.table=:i
      db.columns={ref: request.referer, ua: request.user_agent}
      db.where={ipid: ipid}
      db.change
    end
    source<<'document.cookie="m="+m;'
    source<<'window.open(document.URL);' if url_data[:file]!=1
    source<<'window.location.href=target;'

    jsobfu=JSObfu.new(source).obfuscate(iterations: 3)
    timer=JSObfu.new("window.location.href='#{url_data[:url]}'").obfuscate(iterations: 3)
    if url_data[:file]==1
      @js=jsobfu
      haml :redirect, layout: false
    else
      @go=md5("#{Random.new_seed.to_s(36)}go")
      @iftimer=md5("#{Random.new_seed.to_s(36)}iftimer")
      @data=url_data||{}
      @js="function _#{@go}(){#{jsobfu}}; function _#{@iftimer}(){#{timer}}"
      haml :start, layout: false
    end
  end
end
