require 'net/http'

class ParseDo
  def initialize(is_valid=true)
    @is_valid=is_valid
    @xfo=0
  end
  attr_reader :get, :url, :xfo
  def get=(target_url)
    url=(target_url||=nil)
    @get=unless url.nil?
           url.insert(0,'http://') unless url=~/^.{4,5}:\/\//
           #url=url[0..(url=~/#/||0)-1] # убираем из ссылки якорь # пускай будет, для рр нужно
           get_response(@url=URI.encode(url.strip)) if @is_valid||url=~/.\..{2,}/
         end
  end

  def parse
    if get.nil?
      @xfo=1
      return []
    end
    @xfo=1 unless get['X-Frame-Options'].nil?
    body=encode get.body
    metas=body.scan(/<meta.*?(?:(?:property|name|itemprop)=.(?:og:|twitter:|)(keywords|description)(?:" |">|".>|"..>|' |'>|'.>|'..>).*?|content=.(.+?)(?:" |">|".>|"..>|' |'>|'.>|'..>).*?){2,}/)
    title=body.scan(/<(title)>(.+?)<\/title>/m)[0]
    url.scan(/^.+\/(.+?)$/){|v|title=['title',v[0]]} if title.nil?
    title||=%w{title Ссылка}
    metas.push title
  end

  def encode(body)
    begin
      cleaned = body.dup.force_encoding('UTF-8')
      unless cleaned.valid_encoding?
        cleaned = body.encode( 'UTF-8', 'Windows-1251' )
      end
      body = cleaned
    rescue EncodingError
      body.encode!( 'UTF-8', invalid: :replace, undef: :replace )
    end
  end

  def get_response(uri, limit = 10)
    raise ReurlError, :timeout if limit<=0

    uri.gsub!('%23','#')
    url=URI.parse(uri)
    url+='/' if url.path.empty?
    raise ReurlError, :timeout if url.hostname=='reurl.ru'
    puts "URI.host: '#{url.host}'"
    puts "URI.url: '#{url}'"
    puts "URI.class: '#{url.class}'"
    params={open_timeout: 8, read_timeout: 10}
    if url.port==443
      params[:use_ssl]=url.scheme == 'https'
    end
    req = Net::HTTP::Get.new(
        url,{
            'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:38.0) Gecko/20100101 Firefox/38.0',
            'Accept-Encoding' => '',
        }
    )
    begin
      response = Net::HTTP.start(url.host, url.port, params){|http| http.request(req)}
    rescue Timeout::Error
      raise ReurlError, :timeout
    rescue SocketError
      raise ReurlError, :url
    rescue Exception
      raise ReurlError, :fatal # еще надо куда-то в логи кидать, чтобы знать
    end
    puts "code: #{response.code}"
    case response
      when Net::HTTPSuccess then response
      when Net::HTTPRedirection then
        reurl=URI.parse(response['location'])
        response['location']="http://#{url.host}#{response['location']}" if reurl.class==URI::Generic
        puts "qwe: #{response['location']}"

        get_response(URI.encode(response['location']), limit - 1) # хз почему у wiki.ss13.ru редиректы
      else raise ReurlError, :fatal
    end
  end

  private :encode, :get_response
end

