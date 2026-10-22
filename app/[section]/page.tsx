import { notFound } from 'next/navigation';
import { AppShell } from '@/components/app-shell';
import { ModulePage } from '@/components/module-page';
import { TreasuryPage } from '@/components/treasury-page';
import { ExpensesPage } from '@/components/expenses-page';
import { PaymentsPage } from '@/components/payments-page';
import { PurchasesPage, AssetsPage } from '@/components/purchases-assets-page';
import { ReportsPage } from '@/components/reports-page';
import { modules } from '@/lib/modules';
export function generateStaticParams(){return Object.keys(modules).filter(section=>!['utilisateurs','parametres'].includes(section)).map(section=>({section}));}
export default async function SectionPage({params}:{params:Promise<{section:string}>}){const {section}=await params;if(!modules[section])notFound();return <AppShell>{section==='tresorerie'?<TreasuryPage/>:section==='depenses'?<ExpensesPage/>:section==='paiements'?<PaymentsPage/>:section==='achats'?<PurchasesPage/>:section==='patrimoine'?<AssetsPage/>:section==='rapports'?<ReportsPage/>:<ModulePage section={section}/>}</AppShell>}
