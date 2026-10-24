'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Bell,
  CircleHelp,
  ChevronDown,
  LogOut,
  Search,
  Settings,
  ShieldCheck,
  ArrowRight,
  type LucideIcon,
} from 'lucide-react';
import type { EPCAppRole } from '@/components/access-context';

type NavItem = { key: string; title: string; icon: LucideIcon };
type NavGroup = { label: string; items: NavItem[] };

type TopbarMenusProps = {
  role: EPCAppRole | null;
  userName: string;
  userEmail: string;
  navigationGroups: NavGroup[];
  onLogout: () => void | Promise<void>;
};

const roleLabels: Record<EPCAppRole, string> = {
  admin: 'Administrateur',
  observateur: 'Observateur · lecture seule',
  modification: 'Modification · gestion des données',
};

type OpenMenu = 'search' | 'notifications' | 'profile' | 'help' | null;

export function TopbarMenus({ role, userName, userEmail, navigationGroups, onLogout }: TopbarMenusProps) {
  const router = useRouter();
  const pathname = usePathname();
  const wrapperRef = useRef<HTMLDivElement>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const [openMenu, setOpenMenu] = useState<OpenMenu>(null);
  const [query, setQuery] = useState('');

  const searchResults = useMemo(() => {
    const items = navigationGroups.flatMap((group) =>
      group.items.map((item) => ({ ...item, group: group.label })),
    );
    const normalized = query.trim().toLocaleLowerCase('fr-FR');
    const results = normalized
      ? items.filter((item) => `${item.title} ${item.group}`.toLocaleLowerCase('fr-FR').includes(normalized))
      : items;
    return results.slice(0, 8);
  }, [navigationGroups, query]);

  useEffect(() => {
    if (openMenu === 'search') searchInputRef.current?.focus();
  }, [openMenu]);

  useEffect(() => {
    const handlePointerDown = (event: PointerEvent) => {
      if (!wrapperRef.current?.contains(event.target as Node)) setOpenMenu(null);
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpenMenu(null);
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setOpenMenu('search');
      }
    };
    document.addEventListener('pointerdown', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('pointerdown', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, []);

  function navigateTo(key: string) {
    router.push(key === 'dashboard' ? '/' : `/${key}`);
    setOpenMenu(null);
    setQuery('');
  }

  const initial = userName.trim().slice(0, 1).toLocaleUpperCase('fr-FR') || 'U';
  const canManageSettings = role === 'admin' || role === 'modification';

  return (
    <div className="topbar-actions topbar-menus" ref={wrapperRef}>
      <div className="topbar-search-wrap">
        <div
          className={`global-search ${openMenu === 'search' ? 'global-search-open' : ''}`}
          onClick={() => setOpenMenu('search')}
        >
          <Search size={16} aria-hidden="true" />
          <input
            ref={searchInputRef}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onFocus={() => setOpenMenu('search')}
            placeholder="Rechercher un module…"
            aria-label="Rechercher un module"
            aria-expanded={openMenu === 'search'}
            aria-controls="topbar-search-results"
          />
          <kbd>⌘ K</kbd>
        </div>
        {openMenu === 'search' && (
          <div className="topbar-popover search-popover" id="topbar-search-results" role="listbox" aria-label="Modules disponibles">
            <div className="topbar-popover-heading">Accès rapide</div>
            {searchResults.length ? searchResults.map((item) => {
              const Icon = item.icon;
              const active = pathname === (item.key === 'dashboard' ? '/' : `/${item.key}`);
              return (
                <button
                  type="button"
                  className={`search-result ${active ? 'search-result-active' : ''}`}
                  key={item.key}
                  role="option"
                  aria-selected={active}
                  onClick={() => navigateTo(item.key)}
                >
                  <span className="search-result-icon"><Icon size={16} /></span>
                  <span className="search-result-copy"><strong>{item.title}</strong><small>{item.group}</small></span>
                  <ArrowRight size={14} className="search-result-arrow" />
                </button>
              );
            }) : <div className="topbar-empty">Aucun module ne correspond à cette recherche.</div>}
            <div className="topbar-popover-foot">Appuyez sur Échap pour fermer</div>
          </div>
        )}
      </div>

      <div className="topbar-menu-anchor">
        <button
          type="button"
          className="icon-button notification-button"
          aria-label="Notifications"
          aria-expanded={openMenu === 'notifications'}
          onClick={() => setOpenMenu(openMenu === 'notifications' ? null : 'notifications')}
        >
          <Bell size={18} />
        </button>
        {openMenu === 'notifications' && (
          <div className="topbar-popover notification-popover" role="status">
            <div className="topbar-popover-heading">Notifications</div>
            <div className="notification-empty"><span><Bell size={18} /></span><strong>Aucune notification disponible</strong><p>Les alertes seront affichées ici lorsqu’elles seront connectées aux données de l’établissement.</p></div>
          </div>
        )}
      </div>

      <div className="topbar-menu-anchor topbar-help-anchor">
        <button
          type="button"
          className="topbar-help-trigger"
          aria-label="Besoin d’aide ?"
          aria-expanded={openMenu === 'help'}
          onClick={() => setOpenMenu(openMenu === 'help' ? null : 'help')}
        >
          <CircleHelp size={17} aria-hidden="true" />
          <span>Besoin d’aide ?</span>
        </button>
        {openMenu === 'help' && (
          <div className="topbar-popover topbar-help-popover" role="dialog" aria-label="Aide et ressources">
            <div className="topbar-popover-heading">Besoin d’aide ?</div>
            <div className="topbar-help-content">
              <strong>Consultez le guide d’utilisation.</strong>
              <p>Pour obtenir de l’aide sur une fonctionnalité ou un accès, contactez l’administrateur de l’établissement.</p>
            </div>
          </div>
        )}
      </div>
      <div className="topbar-divider" />
      <div className="topbar-menu-anchor">
        <button
          type="button"
          className="mini-profile topbar-profile-trigger"
          aria-label="Ouvrir le menu du compte"
          aria-expanded={openMenu === 'profile'}
          onClick={() => setOpenMenu(openMenu === 'profile' ? null : 'profile')}
        >
          <span className="avatar avatar-small">{initial}</span>
          <span className="topbar-profile-copy"><strong>{userName}</strong><small>{role ? roleLabels[role] : 'Mode aperçu'}</small></span>
          <ChevronDown size={14} />
        </button>
        {openMenu === 'profile' && (
          <div className="topbar-popover profile-popover">
            <div className="profile-popover-summary"><span className="avatar">{initial}</span><span><strong>{userName}</strong><small>{userEmail || (role ? roleLabels[role] : 'Aucun compte connecté')}</small></span></div>
            <div className="profile-popover-role"><ShieldCheck size={15} /><span>{role ? roleLabels[role] : 'Mode aperçu · lecture seule'}</span></div>
            <div className="profile-popover-links">
              {role === 'admin' && <Link href="/utilisateurs" onClick={() => setOpenMenu(null)}><ShieldCheck size={15} /> Gestion des utilisateurs</Link>}
              {canManageSettings && <Link href="/parametres" onClick={() => setOpenMenu(null)}><Settings size={15} /> Paramètres</Link>}
              <button type="button" onClick={() => { setOpenMenu(null); void onLogout(); }}><LogOut size={15} /> Déconnexion</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
