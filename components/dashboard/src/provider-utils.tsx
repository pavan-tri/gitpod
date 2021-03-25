/**
 * Copyright (c) 2021 Gitpod GmbH. All rights reserved.
 * Licensed under the GNU Affero General Public License (AGPL).
 * See License-AGPL.txt in the project root for license information.
 */

import * as images from './images';
import { gitpodHostUrl } from "./service/service";


function iconForAuthProvider(type: string) {
    switch (type) {
        case "GitHub":
            return images.github
        case "GitLab":
            return images.gitlab
        case "Bitbucket":
            return images.bitbucket
        default:
            break;
    }
}

function simplifyProviderName(host: string) {
    switch (host) {
        case "github.com":
            return "GitHub"
        case "gitlab.com":
            return "GitLab"
        case "bitbucket.org":
            return "Bitbucket"
        default:
            return host;
    }
}

async function openAuthorizeWindow({ host, scopes, onSuccess, onError }: { host: string, scopes?: string[], onSuccess?: () => void, onError?: (error?: string) => void }) {
    const returnTo = gitpodHostUrl.with({ pathname: 'login-success' }).toString();
    const url = gitpodHostUrl.withApi({
        pathname: '/authorize',
        search: `returnTo=${encodeURIComponent(returnTo)}&host=${host}&override=true&scopes=${(scopes || []).join(',')}`
    }).toString();

    const newWindow = window.open(url, "gitpod-connect");
    if (!newWindow) {
        console.log(`Failed to open the authorize window for ${host}`);
        onError && onError("failed");
        return;
    }

    const eventListener = (event: MessageEvent) => {
        // todo: check event.origin

        if (event.data === "auth-success") {
            window.removeEventListener("message", eventListener);

            if (event.source && "close" in event.source && event.source.close) {
                console.log(`Authorization OK. Closing child window.`);
                event.source.close();
            } else {
                // todo: add a button to the /login-success page to close, if this should not work as expected
            }
            onSuccess && onSuccess();
        }
    };
    window.addEventListener("message", eventListener);

    /**
     * As a fallback solution to the cross window messaging, we can try polling for the expected location.
     */

    for (let i = 0; i < 100; i ++) {
        await new Promise(resolve => setTimeout(resolve, 1000));

        if (newWindow.closed) {
            onError && onError("closed");
            return;
        }
        try {
            if (newWindow.document.location.href.toString().includes("login-success")) {
                onSuccess && onSuccess();
                return;
            }
        } catch (error) {
            // expecting cross-origin exception, i.e. when navigating to the external auth server
            continue; 
        }
        if (newWindow.document.location.href.toString().includes("error")) {
            newWindow.close();
            onError && onError("unknown");
            return;
        }
    }
    newWindow.close();
    onError && onError("timeout");
}

export { iconForAuthProvider, simplifyProviderName, openAuthorizeWindow }