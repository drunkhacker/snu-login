require 'openssl'
require 'net/http'
require 'cgi'
require 'nokogiri'
require 'json'

@cookie_sso = {}
@cookie_snu = {}
@cookie_shn = {}

def update_cookies(raw_cookie_str, jar)
    other_pairs = []
    pairs = raw_cookie_str.split(", ").map do |line|
        arr = line.split(";")
        # domain check
        if !line.index("Domain=.snu.ac.kr").nil? || !line.index("domain=.snu.ac.kr").nil?
            other_pairs << arr[0]
        end
        arr[0]
    end.reject {|line| line.index("=").nil?}
    h = pairs.map {|x| i=x.index("="); [x[0...i], x[i+1..-1]]}.to_h
    r = jar.merge(h)

    # 다른쪽 쿠키 jar에도 넣어줌
    h = other_pairs.reject {|line| line.index("=").nil?}.map {|x| i=x.index("="); [x[0...i], x[i+1..-1]]}.to_h

    [:@cookie_sso,:@cookie_snu,:@cookie_shn].each do |jar_name|
        jar = self.instance_variable_get(jar_name)
        jar = jar.merge h
        self.instance_variable_set(jar_name, jar)
    end
    r
end

def get_cookie_str(jar)
    jar.keys.map {|k| "#{k}=#{jar[k]}"}.join("; ")
end

print "ID: "
id = gets.gsub /\n/, ''
print "PWD: "
stty_settings = %x[stty -g]
begin
    %x[stty -echo]
    pw = gets.gsub /\n/, ''
ensure
    %x[stty #{stty_settings}]
end

puts "\nfetching information..."

# user agent 및 기타 잡것들 세팅
headers = {
    "Accept"=>"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
    "Accept-Encoding"=>"gzip,deflate,sdch",
    "Accept-Language"=>"ko-KR,ko;q=0.8,en-US;q=0.6,en;q=0.4,ru;q=0.2",
    "Cache-Control"=>"max-age=0",
    "Connection"=>"keep-alive",
    "User-Agent"=>"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.125 Safari/537.36",
    "Host"=>"my.snu.ac.kr"
}


#0. visit mysnu first
uri = URI.parse("http://my.snu.ac.kr/mysnu/")
#puts "Step 0 - GET #{uri}"
http_snu = Net::HTTP.new(uri.host, uri.port)
resp = http_snu.get(uri.path+"?#{uri.query}", headers)
@cookie_snu = update_cookies(resp.header["Set-Cookie"], @cookie_snu) if resp.header["Set-Cookie"]

headers = headers.merge({
    "Content-Length"=>(271 + id.length + pw.length).to_s,
    "Content-Type"=>"application/x-www-form-urlencoded",
    "Host"=>"sso.snu.ac.kr",
    "Origin"=>"http://my.snu.ac.kr",
    "Referer"=>"http://my.snu.ac.kr/mysnu/portal/"
})

#1. auth_idpwd
params = {
    "si_redirect_address" => CGI.escape("https://sso.snu.ac.kr/snu/ssologin_proc.jsp?si_redirect_address=http://my.snu.ac.kr/mysnu/login?langKnd=ko&loginType=portal"),
    "si_realm" => "SnuUser1",
    "_enpass_login_"=> "submit",
    "langKnd"=> "ko",
    "si_id"=> id,
    "si_pwd"=> pw,
    "btn_login.x"=> "0",
    "btn_login.y"=> "0"
}

uri = URI.parse("https://sso.snu.ac.kr/safeidentity/modules/auth_idpwd")
#puts "=== Step 1 - POST #{uri} ===\n"
http_sso = Net::HTTP.new(uri.host, uri.port)
http_sso.use_ssl = true

post_param = params.map {|k, v| "#{k}=#{v}"}.join("&")
#puts "Request Header:"
#puts headers["Cookie"]
resp = http_sso.post(uri.path, post_param, headers)
#puts "\nResponse Header:"
#puts resp.header["Set-Cookie"]

#2. fcs

@cookie_sso = update_cookies(resp.header["Set-Cookie"], @cookie_sso)
headers["Cookie"] = get_cookie_str(@cookie_sso)
headers["Referer"] = "https://sso.snu.ac.kr/safeidentity/modules/auth_idpwd"
headers["Origin"] = "https://sso.snu.ac.kr"

params = {}
doc = Nokogiri::HTML(resp.body)
doc.search("//form/input").each do |input_tag|
    params[input_tag.attribute("name")] = CGI.escape(input_tag.attribute("value").to_s)
end

post_param = params.map {|k, v| "#{k}=#{v}"}.join("&")
headers["Content-Length"] = post_param.length.to_s
uri.path = "/nls3/fcs"
#puts "\n=== Step 2 - POST #{uri} ===\n"
#puts "Request Header:"
#puts headers["Cookie"]
resp = http_sso.post(uri.path, post_param, headers)
#puts "\nResponse Header:"
#puts resp.header["Set-Cookie"]

#3. tossCredential
@cookie_sso = update_cookies(resp.header["Set-Cookie"], @cookie_sso)
headers["Cookie"] = get_cookie_str(@cookie_sso)
headers.delete "Origin"

doc = Nokogiri::HTML(resp.body)
uri = URI.parse(doc.search("//body/a")[0].attribute("href"))

headers.delete "Content-Length"
headers.delete "Content-Type"

#puts "\n=== Step 3 - GET #{uri} ===\n"
#puts "Request Header:"
#puts headers["Cookie"]
resp = http_sso.get(uri.path, headers)
#puts "Response Header:"
#puts resp.header["Set-Cookie"]

#4. fcs
uri = URI.parse(resp.header["Location"])
#puts "\n=== Step 4 - GET #{uri} ===\n"
#puts "Request Header:"
#puts headers["Cookie"]
resp = http_sso.get(uri.path+"?#{uri.query}", headers)
#puts "\nResponse Header:"
#puts resp.header["Set-Cookie"]

#5. ssologin_proc.jsp
uri = URI.parse(resp.header["Location"])
#puts "\n=== Step 5 - GET #{uri} ===\n"
#puts "Request Header:"
#puts headers["Cookie"]
resp = http_sso.get(uri.path+"?#{uri.query}", headers)
#puts "\nResponse Header:"
#puts resp.header["Set-Cookie"]

#6. login
uri = URI.parse(resp.header["Location"])
#puts "\n=== Step 6 - GET #{uri} ===\n"
#puts "Request Header:"
#puts headers["Cookie"]
http_snu = Net::HTTP.new(uri.host, uri.port)
resp = http_snu.get(uri.path+"?#{uri.query}", headers)
#puts "\nResponse Header:"
#puts resp.header["Set-Cookie"]

#7. mysnu
@cookie_snu = update_cookies(resp.header["Set-Cookie"], @cookie_snu)
headers["Cookie"] = get_cookie_str(@cookie_snu)
headers.delete "Referer"
headers["Host"] = "my.snu.ac.kr"
uri = URI.parse("http://my.snu.ac.kr/mysnu/portal/MS010/04MAIN")
#puts "\n=== Step 7 - GET #{uri} ===\n"
#puts "Request Header:"
#puts headers["Cookie"]
resp = http_snu.get(uri.path+"?#{uri.query}", headers)
#puts "\nResponse Header:"
#puts resp.header["Set-Cookie"]

#    # puts resp.body

#8. shine
uri = URI.parse("https://shine.snu.ac.kr/com/ssoLoginForSWAction.action")
http_shn = Net::HTTP.new(uri.host, uri.port)
http_shn.use_ssl = true
headers["Referer"] = "http://my.snu.ac.kr/mysnu/portal/MS010/ko/TO010.page"
headers["Host"] = "shine.snu.ac.kr"
headers["Cookie"] = get_cookie_str(@cookie_shn)
uri.query = "systemCd=S&pgmCd=S010101&unitBussCd=01&lanCd=ko&lang_knd=ko&evSecurityCode=EV_SECURITY_CODE_#{(Time.now.to_f*1000).to_i}"
#puts "\n=== Step 8 - GET #{uri} ===\n"
#puts "Request Header:"
#puts headers["Cookie"]
resp = http_shn.get(uri.path+"?#{uri.query}", headers)
#puts "\nResponse Header:"
#puts resp.header["Set-Cookie"]

@cookie_shn = update_cookies resp.header["Set-Cookie"], @cookie_shn

#9. haksa
uri = URI.parse("https://shine.snu.ac.kr/com/com/sstm/logn/findUserInfo.action")
post_param = '{"findUsers":{"rType":"3tier","logType":"systemConn","chgUserYn":"N","chgBfUser":"","chgAfUser":""}}'
headers["Host"] = "shine.snu.ac.kr"
headers["Origin"] = "https://shine.snu.ac.kr"
headers["Referer"] = "https://shine.snu.ac.kr/mysnu/mysnu_left.html?_portal=S|01|S010101|ko"
headers["Cookie"] = get_cookie_str(@cookie_shn)
headers["X-Requested-With"] = "XMLHttpRequest"
headers["Content-Type"] = "application/extJs+sua"
#puts "\n=== Step 9 - POST #{uri} ===\n"
#puts "Request Header:"
#puts headers
resp = http_shn.post(uri.path, post_param, headers)
#puts "\nResponse:"
json = JSON.parse resp.body
obj = json["userInfos"][0]
puts
puts obj["REPROLENM"]
puts obj["USERNM"]
puts obj["EMAIL"]

