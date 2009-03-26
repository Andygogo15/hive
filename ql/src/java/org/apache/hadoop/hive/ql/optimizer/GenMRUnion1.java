/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.hadoop.hive.ql.optimizer;

import java.util.List;
import java.util.ArrayList;
import java.util.Stack;
import java.io.Serializable;
import java.io.File;
import java.util.Map;

import org.apache.hadoop.hive.ql.exec.Operator;
import org.apache.hadoop.hive.ql.exec.UnionOperator;
import org.apache.hadoop.hive.ql.exec.Task;
import org.apache.hadoop.hive.ql.plan.mapredWork;
import org.apache.hadoop.hive.ql.lib.Node;
import org.apache.hadoop.hive.ql.lib.NodeProcessor;
import org.apache.hadoop.hive.ql.lib.NodeProcessorCtx;
import org.apache.hadoop.hive.ql.parse.SemanticException;
import org.apache.hadoop.hive.ql.parse.ParseContext;
import org.apache.hadoop.hive.ql.plan.tableDesc;
import org.apache.hadoop.hive.ql.plan.partitionDesc;
import org.apache.hadoop.hive.ql.plan.PlanUtils;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.hive.ql.exec.TaskFactory;
import org.apache.hadoop.hive.ql.plan.fileSinkDesc;
import org.apache.hadoop.hive.conf.HiveConf;
import org.apache.hadoop.hive.ql.exec.OperatorFactory;
import org.apache.hadoop.hive.ql.optimizer.GenMRProcContext.GenMapRedCtx;
import org.apache.hadoop.hive.ql.optimizer.unionproc.UnionProcFactory;
import org.apache.hadoop.hive.ql.optimizer.unionproc.UnionProcContext.UnionParseContext;

/**
 * Processor for the rule - any operator tree followed by union
 */
public class GenMRUnion1 implements NodeProcessor {

  public GenMRUnion1() {
  }

  /**
   * Union Operator encountered .
   * Currently, the algorithm is pretty simple:
   *   If all the sub-queries are map-only, dont do anything.
   *   Otherwise, insert a FileSink on top of all the sub-queries.
   *
   * This can be optimized later on.
   * @param nd the file sink operator encountered
   * @param opProcCtx context
   */
  public Object process(Node nd, Stack<Node> stack, NodeProcessorCtx opProcCtx, Object... nodeOutputs) throws SemanticException {
    UnionOperator union = (UnionOperator)nd;
    GenMRProcContext ctx = (GenMRProcContext)opProcCtx;
    ParseContext parseCtx = ctx.getParseCtx();
    UnionParseContext uPrsCtx = parseCtx.getUCtx().getUnionParseContext(union);
    assert uPrsCtx != null;

    // The plan needs to be broken only if one of the sub-queries involve a map-reduce job
    int numInputs = uPrsCtx.getNumInputs();
    boolean mapOnly = true;
    int pos = 0;
    for (pos = 0; pos < numInputs; pos++) {
      if (!uPrsCtx.getMapOnlySubq(pos)) {
        mapOnly = false;
        break;
      }
    }

    // Map-only subqueries can be optimized in future to not write to a file in future
    Map<Operator<? extends Serializable>, GenMapRedCtx> mapCurrCtx = ctx.getMapCurrCtx();

    if (mapOnly) {
      mapCurrCtx.put((Operator<? extends Serializable>)nd, new GenMapRedCtx(ctx.getCurrTask(), ctx.getCurrTopOp(), ctx.getCurrAliasId()));
      return null;
    }

    Task<? extends Serializable> currTask = ctx.getCurrTask();
    pos = UnionProcFactory.getPositionParent(union, stack);

    // is the current task a root task
    if (uPrsCtx.getRootTask(pos) && (!ctx.getRootTasks().contains(currTask)))
      ctx.getRootTasks().add(currTask);
    
    Task<? extends Serializable> uTask = ctx.getUnionTask(union);

    pos = UnionProcFactory.getPositionParent(union, stack);
    Operator<? extends Serializable> parent = union.getParentOperators().get(pos);   
    mapredWork uPlan = null;

    // union is encountered for the first time
    if (uTask == null) {
      uPlan = GenMapRedUtils.getMapRedWork();
      uTask = TaskFactory.get(uPlan, parseCtx.getConf());
      ctx.setUnionTask(union, uTask);
    }
    else 
      uPlan = (mapredWork)uTask.getWork();
    
    tableDesc tt_desc = 
      PlanUtils.getBinaryTableDesc(PlanUtils.getFieldSchemasFromRowSchema(parent.getSchema(), "temporarycol")); 
    
    // generate the temporary file
    String scratchDir = ctx.getScratchDir();
    int randomid = ctx.getRandomId();
    int pathid   = ctx.getPathId();
    
    String taskTmpDir = (new Path(scratchDir + File.separator + randomid + '.' + pathid)).toString();
    
    pathid++;
    ctx.setPathId(pathid);
    
    // Add the path to alias mapping
    assert uPlan.getPathToAliases().get(taskTmpDir) == null;
    uPlan.getPathToAliases().put(taskTmpDir, new ArrayList<String>());
    uPlan.getPathToAliases().get(taskTmpDir).add(taskTmpDir);
    uPlan.getPathToPartitionInfo().put(taskTmpDir, new partitionDesc(tt_desc, null));
    uPlan.getAliasToWork().put(taskTmpDir, union);
    GenMapRedUtils.setKeyAndValueDesc(uPlan, union);
    
    // Create a file sink operator for this file name
    Operator<? extends Serializable> fs_op =
      OperatorFactory.get
      (new fileSinkDesc(taskTmpDir, tt_desc,
                        parseCtx.getConf().getBoolVar(HiveConf.ConfVars.COMPRESSINTERMEDIATE)),
       parent.getSchema());
    
    assert parent.getChildOperators().size() == 1;
    parent.getChildOperators().set(0, fs_op);

    List<Operator<? extends Serializable>> parentOpList = new ArrayList<Operator<? extends Serializable>>();
    parentOpList.add(parent);
    fs_op.setParentOperators(parentOpList);

    currTask.addDependentTask(uTask);

    // If it is map-only task, add the files to be processed
    if (uPrsCtx.getMapOnlySubq(pos) && uPrsCtx.getRootTask(pos))
      GenMapRedUtils.setTaskPlan(ctx.getCurrAliasId(), ctx.getCurrTopOp(), (mapredWork) currTask.getWork(), false, ctx);

    ctx.setCurrTask(uTask);
    ctx.setCurrAliasId(null);
    ctx.setCurrTopOp(null);

    mapCurrCtx.put((Operator<? extends Serializable>)nd, new GenMapRedCtx(ctx.getCurrTask(), null, null));
    
    return null;
  }
}
