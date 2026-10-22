import type { Metadata } from 'next';
import './globals.css';
export const metadata:Metadata={title:'EPC BETHEL · Gestion scolaire',description:'Plateforme de gestion scolaire, financière et patrimoniale de l’EPC BETHEL ASSEMBLÉES DE DIEU JEAN FOLLY.', icons:{icon:'/icon.png',apple:'/icon.png'}};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="fr"><body>{children}</body></html>}
