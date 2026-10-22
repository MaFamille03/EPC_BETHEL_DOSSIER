'use client';

import { createContext, useContext } from 'react';

export type EPCAppRole = 'admin' | 'observateur' | 'modification';

type AccessContextValue = {
  role: EPCAppRole | null;
  isReadOnly: boolean;
  isAdmin: boolean;
};

const AccessContext = createContext<AccessContextValue>({ role: null, isReadOnly: true, isAdmin: false });

export function AccessProvider({ role, children }: { role: EPCAppRole | null; children: React.ReactNode }) {
  // Fail closed : absence de profil authentifié = lecture seule, jamais un accès en écriture.
  const isReadOnly = role !== 'admin' && role !== 'modification';
  return <AccessContext.Provider value={{ role, isReadOnly, isAdmin: role === 'admin' }}>{children}</AccessContext.Provider>;
}

export function useEPCAccess() {
  return useContext(AccessContext);
}
