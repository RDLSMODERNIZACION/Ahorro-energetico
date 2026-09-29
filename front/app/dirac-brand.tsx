export function DiracBrand({ className = "" }: { className?: string }) {
  return (
    <div className={`dirac-brand ${className}`}>
      <img src="/logodirac.jpeg" alt="Logo Dirac" width={48} height={48} />
      <div><b>DIRAC</b><small>Ahorro Energético</small></div>
    </div>
  );
}
