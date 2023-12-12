#!/bin/bash

curl 'https://www.siepomaga.pl/potrzebujacy/panel/get_data?chart_name=funds&from=2022-11-25&to=2022-12-31' \
  -H 'authority: www.siepomaga.pl' \
  -H 'accept: application/json, text/javascript, */*; q=0.01' \
  -H 'accept-language: en-US,en;q=0.9,pl;q=0.8' \
  -H 'cookie: sp-cookies-v1=off; user_credentials=0765f47932cbb4a6d463ffecc82bf3a3040f245bd8b3e22f6b49255fc359178ec4767cf4c17c3aeda101935d00dda642bec458e43e0b2811f2541475f9653aaf%3A%3A368343%3A%3A2023-09-02T15%3A13%3A32%2B02%3A00; user_logged_in=true; traffic_source=direct; __cflb=04dToYK58AVGjcN3PUdVMJ1vf85aqdAtpH6zKaRNi1; _siepomaga_session=alp0vfVQmLF%2F8rk6SEWUxQFGBybjTHgbfrntPhMmlCIbewbjzf9AqNb0f%2FgCeBo3dMqeGT28C25OOjjwFkGq8PssXIlWlDD2wxksrnqeJCuQJ3eDJ7uwDC6ddLtrUgpcAC1U1arZXCUN4jpdSa%2FQrM%2BtQXD9NeHgYxEl0w%2FrQBPYW3ImGQY3D3vXDSCwWKKLkVS9vsX%2Bpx8jJMrfspLk7swpdArgx42s0%2FppQijmeskoBw8VgNHJi4DGxeOkNyX03u3HgwjJkmi%2F7KTQc8dbd0DrlCtaCWY9AQPK%2FIHtM9hD9M%2F3CkFHNSF%2Boi8%2FBTkNC1kTEmcl4dt2RUhcar7P%2BsqIYPxSQbzozQ2WzcXkUWffTFS4E4WEO86VHbyB6TXAf0GUyJCAYQY1UVe3l8%2B05noJGU1nqe%2F9tZW38xZsUENLPkXHWPK1na6CPPpX2QzsYwkW%2FWyEkdOZDpsEtfpxC6hcfAeMU8jUnpKow2cXLBtj6aM6NMB2jBPJuo%2Fz%2FYx6Ym3DjU8Qle8gWslR2PAR51SisKvW5Y0OcCFo9jrwVNjQ5MKB8WxYaDJyMe84sDOXZWRaTVS3rZNkkbIJ48flwhcwI3Iobu1QA4vHNqdAQc4%2BGqY9P1XIi46uvkQvrscl%2BtqjfD6oR5fSX5hMqz%2BRJ6PvcHCZntIPJWI%2FPF45X3b5%2BcNil62Zu4Cn5N4%3D--ppxl4rr8NMK2L8S7--JB5MIh55zNb85WGuqvO4mg%3D%3D' \
  -H 'dnt: 1' \
  -H 'referer: https://www.siepomaga.pl/potrzebujacy/panel/statystyki' \
  -H 'sec-ch-ua: "Not)A;Brand";v="24", "Chromium";v="116"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "macOS"' \
  -H 'sec-fetch-dest: empty' \
  -H 'sec-fetch-mode: cors' \
  -H 'sec-fetch-site: same-origin' \
  -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36' \
  -H 'x-csrf-token: yqVi8x9JAPOYGAWZbp-SAuGeA-RQjSDwiozyO5msyz-16Z5Op4pfXbE9Rt-1xiasWkmYHcBXjYs_OWfT7lZE2Q' \
  -H 'x-requested-with: XMLHttpRequest' \
  --compressed > sie-pomaga-old-amounts.txt



