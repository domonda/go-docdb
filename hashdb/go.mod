module github.com/domonda/go-docdb/hashdb

go 1.22

replace github.com/domonda/go-docdb => ..

require github.com/domonda/go-docdb v0.0.0-20240702145028-adb148c04ae9 // replaced

require (
	github.com/aws/aws-sdk-go-v2/config v1.27.27
	github.com/aws/aws-sdk-go-v2/service/s3 v1.58.3
	github.com/domonda/go-errs v0.0.0-20240702051036-0e696c849b5f
	github.com/domonda/go-sqldb v0.0.0-20240421041325-ab31a86575fd
	github.com/domonda/go-types v0.0.0-20240729065820-81e069a19467
	github.com/domonda/golog v0.0.0-20240805081224-f870d6f12732
	github.com/ungerik/go-fs v0.0.0-20240702143946-3ecb6733945d
)

require (
	github.com/aws/aws-sdk-go-v2 v1.30.3 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.6.3 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.17.27 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.16.11 // indirect
	github.com/aws/aws-sdk-go-v2/feature/s3/manager v1.17.10
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.3.15 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.6.15 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.8.0 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.3.15 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.11.3 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.3.17 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.11.17 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.17.15 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.22.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.26.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.30.3 // indirect
	github.com/aws/smithy-go v1.20.3 // indirect
	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
	github.com/domonda/go-encjson v0.0.0-20210830085227-1beee57a72d8 // indirect
	github.com/domonda/go-pretty v0.0.0-20240110134850-17385799142f // indirect
	github.com/fsnotify/fsnotify v1.7.0 // indirect
	github.com/lucasb-eyer/go-colorful v1.2.0 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mattn/go-runewidth v0.0.16 // indirect
	github.com/muesli/termenv v0.15.2 // indirect
	github.com/rivo/uniseg v0.4.7 // indirect
	golang.org/x/sys v0.23.0 // indirect
)
