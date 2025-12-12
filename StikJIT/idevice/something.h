//
//  something.h
//  StikDebug
//
//  Created by Stephen on 7/29/25.
//

#ifndef SOMETHING_H
#define SOMETHING_H

#include "idevice.h"
#include <stdint.h>

typedef enum {
    IPA_INSTALLER_OK                   = 0,  /* success                       */
    IPA_INSTALLER_ERR_PAIRING_READ     = 1,  /* could not read pairing file   */
    IPA_INSTALLER_ERR_PROVIDER_CREATE  = 2,  /* idevice_tcp_provider_new fail */
    IPA_INSTALLER_ERR_AFC_CONNECT      = 3,  /* afc_client_connect fail       */
    IPA_INSTALLER_ERR_IPA_READ         = 4,  /* failed to mmap or read IPA    */
    IPA_INSTALLER_ERR_AFC_OPEN         = 5,  /* afc_file_open fail            */
    IPA_INSTALLER_ERR_AFC_WRITE        = 6,  /* afc_file_write fail           */
    IPA_INSTALLER_ERR_INSTALLPROXY     = 7,  /* installation_proxy connect    */
    IPA_INSTALLER_ERR_INSTALL          = 8,  /* installation_proxy_install    */
    IPA_INSTALLER_ERR_INVALID_IP       = 9,  /* inet_pton failed              */
} ipa_installer_error_t;

int install_ipa(const char *ip,
                const char *pairing_file_path,
                const char *udid,
                const char *ipa_path);

#endif /* SOMETHING_H */
