Pod::Spec.new do |s|
s.name                  = 'SafeObjectProxy'
s.version               = '1.0'
s.summary               = 'Make project stronger,defense crash'
s.homepage              = 'https://github.com/heroims/SafeObjectProxy'
s.license               = { :type => 'MIT', :file => 'README.md' }
s.author                = { 'heroims' => 'heroims@163.com' }
s.source                = { :git => 'https://github.com/heroims/SafeObjectProxy.git', :tag => "#{s.version}" }
s.ios.deployment_target = '6.0'
s.osx.deployment_target = '10.7'
s.watchos.deployment_target = '2.0'
s.tvos.deployment_target = '9.0'
s.source_files          = 'SafeObjectProxy/*.{h,m}'
s.requires_arc          = true
end


