Pod::Spec.new do |s|
s.name             = "HYDBCache"
s.version          = "0.6"
s.summary          = "A Cache Include Memory Cache and DiskCache"

s.description      = "A Cache Include Memory Cache and DiskCache,Provide For HYTeam Use."

s.homepage         = "https://github.com/fangyuxi/HYDBCache"
s.license          = 'MIT'
s.author           = { "fangyuxi" => "xcoder.fang@gmail.com" }
s.source           = { :git => "https://github.com/fangyuxi/HYDBCache.git", :tag => s.version.to_s }

s.platform     = :ios, '7.0'
s.requires_arc = true

s.source_files = 'HYCache/Classes/**/*'
end
