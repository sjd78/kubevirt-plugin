import { MouseEvent, useRef, useState } from 'react';

import { useInstanceTypeVMStore } from '@catalog/CreateFromInstanceTypes/state/useInstanceTypeVMStore';
import { instanceTypeActionType } from '@catalog/CreateFromInstanceTypes/state/utils/types';
import { logITFlowEvent } from '@kubevirt-utils/extensions/telemetry/telemetry';
import { INSTANCETYPE_SELECTED } from '@kubevirt-utils/extensions/telemetry/utils/constants';
import { useClickOutside } from '@kubevirt-utils/hooks/useClickOutside/useClickOutside';

import { UseInstanceTypeCardMenuSectionValues } from '../utils/types';

const useInstanceTypeCardMenuSection = (): UseInstanceTypeCardMenuSectionValues => {
  const [activeMenu, setActiveMenu] = useState<string>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  const { setInstanceTypeVMState } = useInstanceTypeVMStore();

  const onMenuToggle = (event?: MouseEvent, menuID?: string) => {
    event?.stopPropagation(); // Stop handleClickOutside from handling
    setActiveMenu((prevActiveMenu) => (prevActiveMenu === menuID ? null : menuID));
  };

  const onMenuSelect = (itName: string) => {
    setActiveMenu(null);

    setInstanceTypeVMState({
      payload: { name: itName, namespace: null },
      type: instanceTypeActionType.setSelectedInstanceType,
    });

    logITFlowEvent(INSTANCETYPE_SELECTED, null, {
      selectedInstanceType: itName,
    });
  };

  useClickOutside([menuRef], onMenuToggle);
  return { activeMenu, menuRef, onMenuSelect, onMenuToggle };
};

export default useInstanceTypeCardMenuSection;
