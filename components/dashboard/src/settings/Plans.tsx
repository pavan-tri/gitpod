/**
 * Copyright (c) 2021 Gitpod GmbH. All rights reserved.
 * Licensed under the GNU Affero General Public License (AGPL).
 * See License-AGPL.txt in the project root for license information.
 */

import SelectableCard from "../components/SelectableCard";
import { SettingsPage } from "./SettingsPage";

export default function Plans() {
    return <div>
        <SettingsPage title='Plans' subtitle='Manage account usage and billing.'>
            <h3>Plans</h3>
            <div className="flex space-x-2">
                <SelectableCard className="w-56 h-80" title="FREE" selected={true} onClick={() => {}}>
                    <div className="mt-5 mb-5 flex flex-col items-center justify-center">
                        <p className="text-3xl text-gray-500 font-bold">50</p>
                        <p className="text-base text-gray-500 font-bold">hours</p>
                    </div>
                    <div className="flex-grow">
                        <p>✓ Public Repositories</p>
                        <p>✓ 4 Parallel Workspaces</p>
                        <p>✓ 30 min Timeout</p>
                    </div>
                    <div>
                        <p className="text-center mb-2 mt-4">FREE</p>
                        <button className="w-full">Current Plan</button>
                    </div>
                </SelectableCard>
                <SelectableCard className="w-56 h-80" title="PERSONAL" selected={false} onClick={() => {}}>
                    <div className="mt-5 mb-5 flex flex-col items-center justify-center">
                        <p className="text-3xl text-gray-500 font-bold">100</p>
                        <p className="text-base text-gray-500 font-bold">hours</p>
                    </div>
                    <div className="flex-grow">
                        <p>← Everything in Free</p>
                        <p>✓ Private Repositories</p>
                    </div>
                    <div>
                        <p className="text-center mb-2 mt-4">€8 per month</p>
                        <button className="w-full border-green-600 text-green-600 bg-white hover:border-green-800 hover:text-green-800">Upgrade</button>
                    </div>
                </SelectableCard>
            </div>
        </SettingsPage>
    </div>;
}

