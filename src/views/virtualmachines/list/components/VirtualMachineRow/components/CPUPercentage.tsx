import React, { FC } from 'react';

import { V1VirtualMachine } from '@kubevirt-ui/kubevirt-api/kubevirt';
import { getName, getNamespace } from '@kubevirt-utils/resources/shared';
import { NO_DATA_DASH } from '@kubevirt-utils/resources/vm/utils/constants';
import { isEmpty } from '@kubevirt-utils/utils/utils';
import { getCPUUsagePercentage } from '@virtualmachines/list/metrics';
import { isRunning } from '@virtualmachines/utils';

type CPUPercentageProps = {
  vm: V1VirtualMachine;
};

const CPUPercentage: FC<CPUPercentageProps> = ({ vm }) => {
  const cpuUsagePercentage = getCPUUsagePercentage(getName(vm), getNamespace(vm));

  if (isEmpty(cpuUsagePercentage) || !isRunning(vm)) return <span>{NO_DATA_DASH}</span>;

  return <span>{cpuUsagePercentage.toFixed(2)}%</span>;
};

export default CPUPercentage;
