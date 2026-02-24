import React, { useMemo } from 'react';

import { useDataViewTableSort } from '@kubevirt-utils/hooks/useDataViewTableSort/useDataViewTableSort';
import { generateRows } from '@kubevirt-utils/hooks/useDataViewTableSort/utils';
import { useKubevirtTranslation } from '@kubevirt-utils/hooks/useKubevirtTranslation';
import { isEmpty } from '@kubevirt-utils/utils/utils';
import { DataViewTable } from '@patternfly/react-data-view';

import { getConditionRowId, getConditionsColumns } from './conditionsTableDefinition';

export enum K8sResourceConditionStatus {
  False = 'False',
  True = 'True',
  Unknown = 'Unknown',
}

export type K8sResourceCondition = {
  lastTransitionTime?: string;
  message?: string;
  reason?: string;
  status: keyof typeof K8sResourceConditionStatus;
  type: string;
};

export type ConditionsProps = {
  conditions: K8sResourceCondition[];
};

export const ConditionsTable: React.FC<ConditionsProps> = ({ conditions }) => {
  const { t } = useKubevirtTranslation();

  const columns = useMemo(() => getConditionsColumns(t), [t]);
  const { sortedData, tableColumns } = useDataViewTableSort(conditions, columns, 'type');

  const rows = useMemo(
    () => generateRows(sortedData, columns, undefined, getConditionRowId),
    [sortedData, columns],
  );

  if (isEmpty(conditions)) {
    return <div className="pf-v6-u-text-align-center">{t('No conditions found')}</div>;
  }

  return <DataViewTable aria-label={t('Conditions table')} columns={tableColumns} rows={rows} />;
};

ConditionsTable.displayName = 'ConditionsTable';
