module github.com/domonda/go-docdb/hashdb

go 1.23

replace github.com/domonda/go-docdb => ..

require github.com/domonda/go-docdb v0.0.0-00010101000000-000000000000 // replaced

require (
	github.com/aws/aws-sdk-go-v2/config v1.29.2
	github.com/aws/aws-sdk-go-v2/service/s3 v1.74.1
	github.com/domonda/go-errs v0.0.0-20240702051036-0e696c849b5f
	github.com/domonda/go-sqldb v0.0.0-20241227145140-d73d1a3d4b52
	github.com/domonda/go-types v0.0.0-20250118214036-e6b16f981e81
	github.com/domonda/golog v0.0.0-20241212121502-ba358db15e0b
	github.com/ungerik/go-fs v0.0.0-20250123134246-3ac71b34b8e3
)

require (
	github.com/aws/aws-sdk-go-v2 v1.34.0 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.6.8 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.17.55 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.16.25 // indirect
	github.com/aws/aws-sdk-go-v2/feature/s3/manager v1.17.54
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.3.29 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.6.29 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.8.2 // indirect
	github.com/aws/aws-sdk-go-v2/internal/v4a v1.3.29 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.12.2 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/checksum v1.5.3 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.12.10 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/s3shared v1.18.10 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.24.12 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.28.11 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.33.10 // indirect
	github.com/aws/smithy-go v1.22.2 // indirect
	github.com/aymanbagabas/go-osc52/v2 v2.0.1 // indirect
	github.com/domonda/go-encjson v0.0.0-20210830085227-1beee57a72d8 // indirect
	github.com/domonda/go-pretty v0.0.0-20240110134850-17385799142f // indirect
	github.com/fsnotify/fsnotify v1.8.0 // indirect
	github.com/lib/pq v1.10.9 // indirect
	github.com/lucasb-eyer/go-colorful v1.2.0 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mattn/go-runewidth v0.0.16 // indirect
	github.com/muesli/termenv v0.15.2 // indirect
	github.com/rivo/uniseg v0.4.7 // indirect
	golang.org/x/sys v0.29.0 // indirect
)
