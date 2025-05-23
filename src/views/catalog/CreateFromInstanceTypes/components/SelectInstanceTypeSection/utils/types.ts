import { MutableRefObject } from 'react';

import { InstanceTypeSize } from '@kubevirt-utils/resources/instancetype/types';

export enum InstanceTypeCategory {
  ComputeIntensive = 'ComputeIntensive',
  GeneralPurpose = 'GeneralPurpose',
  GpuResourcesAttached = 'GpuResourcesAttached',
  MemoryIntensive = 'MemoryIntensive',
}

export type InstanceTypeSizeDetails = {
  cpus: number;
  label: string;
  memory: string;
  name: InstanceTypeSize;
};

export type CategoryDetails = {
  Icon: any;
  instanceTypes: InstanceTypeSizeDetails[];
  prefix: string;
  prefixLabel: string;
  seriesLabel: string;
  title: string;
};

export type CategoryDetailsMap = { [key in InstanceTypeCategory]: CategoryDetails };

export type UseInstanceTypeCardMenuSectionValues = {
  activeMenu: string;
  menuRef: MutableRefObject<HTMLDivElement>;
  onMenuSelect: (itName: string) => void;
  onMenuToggle: (event?: React.MouseEvent, menuID?: string) => void;
};
