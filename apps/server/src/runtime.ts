export class AdapterNotInstalled extends Error {
  readonly code = "adapter-not-installed";

  constructor() {
    super(
      "Nenhum adaptador de provedor está instalado nesta versão. Nenhuma chamada foi feita e nenhum consumo foi registrado.",
    );
    this.name = "AdapterNotInstalled";
  }
}

export function startProviderRun(): never {
  throw new AdapterNotInstalled();
}
