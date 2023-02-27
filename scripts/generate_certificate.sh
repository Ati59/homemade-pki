#!/usr/bin/env bash

BASE_DIR="."

PKI_DIR=${BASE_DIR}/pki
PKI_CA_DIR=${PKI_DIR}/ca
PKI_INTERMEDIATE_DIR=${PKI_DIR}/intermediate

function log() {
  printf "$(date +%H:%M:%S) - ${1}\n"
}

if [[ $# == 0 ]]; then
  log "ERROR: No SAN has been precised on arguments !"
  log "ex: ./scripts/generate_certificate.sh httpbin.localhost httpbin-2.localhost"
  exit 1
fi

NUM_ARG=$#
IFS=', ' read -r -a ARGS <<< "$*"

function check_parameters() {
  for id in $(seq 0 1 $((NUM_ARG-1))); do
     SAN_LIST+="DNS.${id} = ${ARGS[id]}\n"
  done
}

function make_ca() {
  log "--------------- CA ---------------"

  log "Creating PKI CA structure files in ${PKI_CA_DIR}"
  mkdir -p ${PKI_CA_DIR}/certs ${PKI_CA_DIR}/crl ${PKI_CA_DIR}/newcerts ${PKI_CA_DIR}/private
  chmod 700 ${PKI_CA_DIR}/private
  touch ${PKI_CA_DIR}/index.txt
  echo 1000 > ${PKI_CA_DIR}/serial

  log "Creating openssl configuration files ${PKI_CA_DIR}/openssl.ini"
  cat config/openssl_ca.ini | awk '{gsub("%ROOT_DIR%", "'${PKI_CA_DIR}'"); print}' > ${PKI_CA_DIR}/openssl.ini
  cat config/default.ini >> ${PKI_CA_DIR}/openssl.ini
  echo "commonName_default = ROOT" >> ${PKI_CA_DIR}/openssl.ini
  cat config/common.ini >> ${PKI_CA_DIR}/openssl.ini

  log "Creating CA private key ${PKI_CA_DIR}/private/ca.key.pem"
  openssl genrsa -aes256 -out ${PKI_CA_DIR}/private/ca.key.pem 4096
  chmod 400 ${PKI_CA_DIR}/private/ca.key.pem

  log "Creating CA certificate ${PKI_CA_DIR}/certs/ca.cert.pem"
  openssl req -config ${PKI_CA_DIR}/openssl.ini \
        -key ${PKI_CA_DIR}/private/ca.key.pem \
        -new -x509 -days 7300 -sha256 -extensions v3_ca \
        -out ${PKI_CA_DIR}/certs/ca.cert.pem
  chmod 444 ${PKI_CA_DIR}/certs/ca.cert.pem
}

function make_intermediate() {
  log "\n--------------- INTERMEDIATE ---------------"

  log "Creating PKI intermediate structure files in ${PKI_INTERMEDIATE_DIR}"
  mkdir -p ${PKI_INTERMEDIATE_DIR}/certs ${PKI_INTERMEDIATE_DIR}/crl ${PKI_INTERMEDIATE_DIR}/csr ${PKI_INTERMEDIATE_DIR}/newcerts ${PKI_INTERMEDIATE_DIR}/private
  chmod 700 ${PKI_INTERMEDIATE_DIR}/private
  touch ${PKI_INTERMEDIATE_DIR}/index.txt
  echo 1000 > ${PKI_INTERMEDIATE_DIR}/serial
  echo 1000 > ${PKI_INTERMEDIATE_DIR}/crlnumber

  log "Creating openssl configuration files ${PKI_INTERMEDIATE_DIR}/openssl.ini"
  cat config/openssl_intermediate.ini | awk '{gsub("%ROOT_DIR%", "'${PKI_INTERMEDIATE_DIR}'"); print}' > ${PKI_INTERMEDIATE_DIR}/openssl.ini
  cat config/default.ini >> ${PKI_INTERMEDIATE_DIR}/openssl.ini
  echo "commonName_default = INTERMEDIATE" >> ${PKI_INTERMEDIATE_DIR}/openssl.ini
  cat config/common.ini >> ${PKI_INTERMEDIATE_DIR}/openssl.ini

  log "Creating intermediate private key ${PKI_INTERMEDIATE_DIR}/private/intermediate.key.pem"
  openssl genrsa -aes256 \
        -out ${PKI_INTERMEDIATE_DIR}/private/intermediate.key.pem 4096
  chmod 400 ${PKI_INTERMEDIATE_DIR}/private/intermediate.key.pem

  log "Creating intermediate CSR ${PKI_INTERMEDIATE_DIR}/certs/ca.cert.pem"
  openssl req -config ${PKI_INTERMEDIATE_DIR}/openssl.ini -new -sha256 \
        -key ${PKI_INTERMEDIATE_DIR}/private/intermediate.key.pem \
        -out ${PKI_INTERMEDIATE_DIR}/csr/intermediate.csr.pem

  log "Creating intermediate certificate ${PKI_INTERMEDIATE_DIR}/certs/ca.cert.pem"
  openssl ca -config ${PKI_CA_DIR}/openssl.ini -extensions v3_intermediate_ca \
        -days 3650 -notext -md sha256 \
        -in ${PKI_INTERMEDIATE_DIR}/csr/intermediate.csr.pem \
        -out ${PKI_INTERMEDIATE_DIR}/certs/intermediate.cert.pem
  chmod 444 ${PKI_INTERMEDIATE_DIR}/certs/intermediate.cert.pem

  log "Creating CA chain file ${PKI_INTERMEDIATE_DIR}/certs/ca-chain.cert.pem"
  cat  ${PKI_INTERMEDIATE_DIR}/certs/intermediate.cert.pem  ${PKI_CA_DIR}/certs/ca.cert.pem > ${PKI_INTERMEDIATE_DIR}/certs/ca-chain.cert.pem
  chmod 444  ${PKI_INTERMEDIATE_DIR}/certs/ca-chain.cert.pem
}

function make_multisan() {
  log "\n--------------- MULTISAN ---------------"

  log "Creating openssl configuration files ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini"
  cat config/openssl_intermediate.ini | awk '{gsub("%ROOT_DIR%", "'${PKI_INTERMEDIATE_DIR}'"); print}' > ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini
  cat config/default.ini >> ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini
  echo "commonName_default = MULTISAN" >> ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini
  cat config/common.ini >> ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini
  cat config/san.ini >> ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini
  printf "${SAN_LIST}" >> ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini

  log "Creating certificate private key ${PKI_INTERMEDIATE_DIR}/private/multisan.key.pem"
  openssl genrsa -aes256 \
      -out ${PKI_INTERMEDIATE_DIR}/private/multisan.key.pem 2048
  chmod 400 ${PKI_INTERMEDIATE_DIR}/private/multisan.key.pem

  log "Creating unprotected key file ${PKI_INTERMEDIATE_DIR}/private/multisan-unprotected.key.pem"
  openssl rsa -in ${PKI_INTERMEDIATE_DIR}/private/multisan.key.pem -out ${PKI_INTERMEDIATE_DIR}/private/multisan-unprotected.key.pem

  log "Creating multisan CSR ${PKI_INTERMEDIATE_DIR}/csr/multisan.csr.pem"
  openssl req -config ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini \
      -key ${PKI_INTERMEDIATE_DIR}/private/multisan.key.pem \
      -new -sha256 -out ${PKI_INTERMEDIATE_DIR}/csr/multisan.csr.pem

  log "Creating multisan certificate ${PKI_INTERMEDIATE_DIR}/certs/multisan.cert.pem"
  openssl ca -config ${PKI_INTERMEDIATE_DIR}/openssl_multisan.ini \
        -extensions server_cert -days 375 -notext -md sha256 \
        -in ${PKI_INTERMEDIATE_DIR}/csr/multisan.csr.pem \
        -out ${PKI_INTERMEDIATE_DIR}/certs/multisan.cert.pem
  chmod 444 ${PKI_INTERMEDIATE_DIR}/certs/multisan.cert.pem

  log "Creating multisan full-chain certificate ${PKI_INTERMEDIATE_DIR}/multisan-full-chain-certificate.pem"
  cat ${PKI_INTERMEDIATE_DIR}/certs/multisan.cert.pem ${PKI_INTERMEDIATE_DIR}/certs/intermediate.cert.pem ${PKI_CA_DIR}/certs/ca.cert.pem > ${PKI_INTERMEDIATE_DIR}/multisan-full-chain-certificate.pem
}

check_parameters

make_ca
make_intermediate
make_multisan

log "--------------------------------------------------------"
log "CA chain certificates : ${PKI_INTERMEDIATE_DIR}/certs/ca-chain.cert.pem"
log "Multisan certificate : ${PKI_INTERMEDIATE_DIR}/certs/multisan.cert.pem"
log "Multisan full-chain certificate : ${PKI_INTERMEDIATE_DIR}/multisan-full-chain-certificate.pem"
log "Multisan key : ${PKI_INTERMEDIATE_DIR}/private/multisan.key.pem"
log "Multisan key (unprotected) : ${PKI_INTERMEDIATE_DIR}/private/multisan-unprotected.key.pem"
log "--------------------------------------------------------"

exit 0